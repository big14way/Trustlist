// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAgenticCommerce} from "./interfaces/IAgenticCommerce.sol";
import {IDisputePolicy} from "./interfaces/IDisputePolicy.sol";
import {IEvaluatorRouter} from "./interfaces/IEvaluatorRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title HireRail
/// @notice A thin wrapper over the ERC-8183 AgenticCommerce kernel that
/// turns the multi call hire sequence into one transaction tied to an
/// ERC-8004 agent id, with events an indexer can follow.
///
/// Two settlement modes, because the kernel supports two and they make
/// genuinely different promises:
///
///  - Direct: this contract is the job's evaluator, and the only code path
///    that releases escrow is `accept`, which reverts for anyone except the
///    recorded hirer. The hirer pays when they are satisfied and the money
///    moves in the same block. The agent is trusting the hirer; the hirer is
///    never trusting us, because this contract has no discretion to release
///    on its own. If the hirer never accepts, the escrow returns to the
///    hirer after the deadline. This is not dispute protected and the UI
///    must not describe it as such.
///
///  - Protected: the EvaluatorRouter is the evaluator and the hook, and a
///    whitelisted policy decides. On BSC mainnet that policy is
///    OptimisticPolicy with a seven day dispute window baked into its
///    bytecode as an immutable. Neither side can act unilaterally, and
///    settlement is permissionless once the window closes.
/// @dev The kernel requires the EvaluatorRouter to be both the job's
/// evaluator and its hook, and the policy must be bound by the job's client
/// while the job is still Open. Because HireRail is the client from the
/// kernel's point of view, it records the real hirer and is the only path
/// back to them: reclaim always pays the recorded hirer and nobody else.
/// It never holds funds beyond the single hire it is executing, and never
/// holds an approval beyond the exact amount mid transaction.
/// Pausable is a hackathon safety valve, owner only, disclosed in the README.
contract HireRail is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Mode {
        Direct,
        Protected
    }

    /// @notice The ERC-8183 kernel this rail wraps.
    IAgenticCommerce public immutable kernel;
    /// @notice Hook used for Direct jobs. The kernel demands a hook that
    /// advertises IACPHook, and the router refuses jobs it does not
    /// evaluate, so Direct mode needs its own.
    address public immutable directHook;
    /// @notice The EvaluatorRouter: evaluator and hook for every job we open.
    IEvaluatorRouter public immutable router;
    /// @notice The dispute policy bound to every job we open.
    address public immutable policy;
    /// @notice The kernel's payment token, read at deployment.
    IERC20 public immutable token;

    /// @notice The hirer behind each job this rail opened.
    mapping(uint256 => address) public hirerOf;
    /// @notice The ERC-8004 agent id behind each job this rail opened.
    mapping(uint256 => uint256) public agentOf;
    /// @notice The escrowed budget of each job, so a refund can be bounded
    /// to the job it belongs to.
    mapping(uint256 => uint256) public budgetOf;
    /// @notice Whether a job's refund has already been forwarded to its
    /// hirer, so it can never be forwarded twice.
    mapping(uint256 => bool) public refundForwarded;
    /// @notice Which settlement mode each job was opened under.
    mapping(uint256 => Mode) public modeOf;

    event Hired(
        uint256 indexed jobId,
        uint256 indexed agentId,
        address indexed hirer,
        address provider,
        uint256 budget,
        uint64 deadline,
        bytes32 specHash,
        Mode mode
    );
    event Accepted(uint256 indexed jobId, address indexed hirer, uint256 paid);
    event WorkRejected(uint256 indexed jobId, address indexed hirer, uint256 refunded);
    event Settled(uint256 indexed jobId, address indexed caller);
    event Reclaimed(uint256 indexed jobId, address indexed hirer, uint256 refunded);
    event Refunded(uint256 indexed jobId, address indexed hirer, uint256 amount);

    error DeadlineInPast();
    error ZeroBudget();
    error ZeroProvider();
    error UnknownJob();
    error NothingToRefund();
    error JobNotRefundable();
    error NotHirer();
    error WrongMode();
    error DeadlineTooSoon();

    /// @dev The kernel rejects any deadline that is not strictly more than
    /// five minutes out, so we reject those earlier with a clearer error.
    uint64 public constant MIN_DEADLINE_LEAD = 5 minutes;

    /// @notice The bound's policy dispute window, read once at deployment.
    /// A protected job must outlive it or it expires before it can settle.
    uint64 public immutable disputeWindow;

    constructor(address kernel_, address router_, address policy_, address directHook_) Ownable(msg.sender) {
        kernel = IAgenticCommerce(kernel_);
        router = IEvaluatorRouter(router_);
        policy = policy_;
        directHook = directHook_;
        token = IERC20(IAgenticCommerce(kernel_).paymentToken());
        // Read it here so a policy we cannot interpret fails at deploy time
        // rather than stranding somebody's escrow later.
        disputeWindow = IDisputePolicy(policy_).disputeWindow();
    }

    /// @notice Open, bind, budget, and fund an ERC-8183 job in one
    /// transaction. Pulls exactly `budget` of the kernel's payment token from
    /// the caller.
    /// @param agentId The ERC-8004 agent id being hired, for indexing.
    /// @param provider The address that will deliver the work.
    /// @param budget Exact amount escrowed, pulled from the caller.
    /// @param deadline Unix time after which the job can be expired and the
    /// escrow reclaimed.
    /// @param specHash keccak256 of the plaintext job spec.
    /// @param description Job description stored by the kernel.
    /// @return jobId The kernel's job id.
    function hire(
        uint256 agentId,
        address provider,
        uint256 budget,
        uint64 deadline,
        bytes32 specHash,
        string calldata description,
        Mode mode
    ) external whenNotPaused nonReentrant returns (uint256 jobId) {
        if (deadline <= block.timestamp + MIN_DEADLINE_LEAD) revert DeadlineTooSoon();
        if (budget == 0) revert ZeroBudget();
        if (provider == address(0)) revert ZeroProvider();

        if (mode == Mode.Protected) {
            // A protected job settles only after the dispute window closes,
            // so a deadline inside that window would expire the job before
            // it could ever pay out. Refuse rather than strand the escrow.
            if (deadline <= block.timestamp + disputeWindow) revert DeadlineTooSoon();
            // The router enforces that it is both evaluator and hook, and
            // only the job's client may bind the policy.
            jobId = kernel.createJob(provider, address(router), deadline, description, address(router));
            router.registerJob(jobId, policy);
        } else {
            // This contract is the evaluator, with release bound to the
            // hirer in `accept`. registerJob is deliberately not called:
            // the router only accepts jobs it evaluates.
            jobId = kernel.createJob(provider, address(this), deadline, description, directHook);
        }

        kernel.setBudget(jobId, budget, "");

        hirerOf[jobId] = msg.sender;
        agentOf[jobId] = agentId;
        budgetOf[jobId] = budget;
        modeOf[jobId] = mode;

        token.safeTransferFrom(msg.sender, address(this), budget);
        token.forceApprove(address(kernel), budget);
        kernel.fund(jobId, budget, "");

        emit Hired(jobId, agentId, msg.sender, provider, budget, deadline, specHash, mode);
    }

    /// @notice Release escrow to the provider. Direct jobs only, and only
    /// the hirer who paid may call it.
    /// @dev This contract is the evaluator for Direct jobs, which is what
    /// lets the payout land in the same block. The authority to use that
    /// position lives entirely in the check below: there is no owner path,
    /// no admin path, and no code path by which this contract releases a
    /// hirer's escrow without the hirer asking.
    function accept(uint256 jobId) external nonReentrant {
        address hirer = hirerOf[jobId];
        if (hirer == address(0)) revert UnknownJob();
        if (msg.sender != hirer) revert NotHirer();
        if (modeOf[jobId] != Mode.Direct) revert WrongMode();

        kernel.complete(jobId, bytes32(0), "");
        emit Accepted(jobId, hirer, budgetOf[jobId]);
    }

    /// @notice Refuse the delivery and take the escrow back. Direct jobs
    /// only, hirer only. The kernel refunds its client, which is this
    /// contract, so the tokens are forwarded onward in the same call.
    function rejectWork(uint256 jobId) external nonReentrant {
        address hirer = hirerOf[jobId];
        if (hirer == address(0)) revert UnknownJob();
        if (msg.sender != hirer) revert NotHirer();
        if (modeOf[jobId] != Mode.Direct) revert WrongMode();

        uint256 before = token.balanceOf(address(this));
        kernel.reject(jobId, bytes32(0), "");
        uint256 returned = token.balanceOf(address(this)) - before;
        if (returned > 0) {
            refundForwarded[jobId] = true;
            token.safeTransfer(hirer, returned);
        }
        emit WorkRejected(jobId, hirer, returned);
    }

    /// @notice Forward a settlement to the EvaluatorRouter. Permissionless,
    /// exactly as the router is: anyone may push a decided job to payout.
    /// @dev A rejected job refunds the kernel's client, and this contract is
    /// that client. Any tokens that land here as a result are forwarded to
    /// the person who actually paid, in the same transaction.
    function settle(uint256 jobId, bytes calldata evidence) external nonReentrant {
        address hirer = hirerOf[jobId];
        if (hirer == address(0)) revert UnknownJob();
        if (modeOf[jobId] != Mode.Protected) revert WrongMode();

        uint256 before = token.balanceOf(address(this));
        router.settle(jobId, evidence);
        uint256 returned = token.balanceOf(address(this)) - before;

        emit Settled(jobId, msg.sender);
        if (returned > 0) {
            refundForwarded[jobId] = true;
            token.safeTransfer(hirer, returned);
            emit Refunded(jobId, hirer, returned);
        }
    }

    /// @notice Push a stranded refund to the hirer it belongs to. Needed
    /// when a job was settled or expired without going through this
    /// contract, which leaves the escrow sitting here as the kernel's
    /// client. Permissionless, bounded to that job's own budget, and
    /// payable only to the recorded hirer.
    function forwardRefund(uint256 jobId) external nonReentrant {
        address hirer = hirerOf[jobId];
        if (hirer == address(0)) revert UnknownJob();
        if (refundForwarded[jobId]) revert NothingToRefund();

        IAgenticCommerce.JobStatus status = kernel.getJob(jobId).status;
        if (status != IAgenticCommerce.JobStatus.Rejected && status != IAgenticCommerce.JobStatus.Expired) {
            revert JobNotRefundable();
        }

        uint256 balance = token.balanceOf(address(this));
        uint256 owed = budgetOf[jobId];
        uint256 amount = balance < owed ? balance : owed;
        if (amount == 0) revert NothingToRefund();

        refundForwarded[jobId] = true;
        token.safeTransfer(hirer, amount);
        emit Refunded(jobId, hirer, amount);
    }

    /// @notice Expire a past deadline job and return the escrow to the
    /// hirer who paid for it. Permissionless to call; funds only ever move
    /// to the recorded hirer.
    function reclaim(uint256 jobId) external nonReentrant {
        address hirer = hirerOf[jobId];
        if (hirer == address(0)) revert UnknownJob();

        // markExpired is idempotent from our side: if the router has already
        // expired the job, go straight to claiming the refund.
        try router.markExpired(jobId) {} catch {}

        uint256 before = token.balanceOf(address(this));
        kernel.claimRefund(jobId);
        uint256 refunded = token.balanceOf(address(this)) - before;
        if (refunded == 0) revert NothingToRefund();

        refundForwarded[jobId] = true;
        token.safeTransfer(hirer, refunded);
        emit Reclaimed(jobId, hirer, refunded);
    }

    /// @notice Hackathon safety valve, owner only, disclosed in the README.
    /// Pausing blocks new hires and never traps an existing job: settle and
    /// reclaim stay open.
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
