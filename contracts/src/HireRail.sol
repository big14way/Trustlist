// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAgenticCommerce} from "./interfaces/IAgenticCommerce.sol";
import {IEvaluatorRouter} from "./interfaces/IEvaluatorRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title HireRail
/// @notice A thin wrapper over the ERC-8183 AgenticCommerce kernel that
/// turns the four call hire sequence (open the job, bind the dispute policy,
/// set the budget, fund the escrow) into one transaction tied to an ERC-8004
/// agent id, with events an indexer can follow.
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

    /// @notice The ERC-8183 kernel this rail wraps.
    IAgenticCommerce public immutable kernel;
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

    event Hired(
        uint256 indexed jobId,
        uint256 indexed agentId,
        address indexed hirer,
        address provider,
        uint256 budget,
        uint64 deadline,
        bytes32 specHash
    );
    event Settled(uint256 indexed jobId, address indexed caller);
    event Reclaimed(uint256 indexed jobId, address indexed hirer, uint256 refunded);
    event Refunded(uint256 indexed jobId, address indexed hirer, uint256 amount);

    error DeadlineInPast();
    error ZeroBudget();
    error ZeroProvider();
    error UnknownJob();
    error NothingToRefund();
    error JobNotRefundable();

    constructor(address kernel_, address router_, address policy_) Ownable(msg.sender) {
        kernel = IAgenticCommerce(kernel_);
        router = IEvaluatorRouter(router_);
        policy = policy_;
        token = IERC20(IAgenticCommerce(kernel_).paymentToken());
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
        string calldata description
    ) external whenNotPaused nonReentrant returns (uint256 jobId) {
        if (deadline <= block.timestamp) revert DeadlineInPast();
        if (budget == 0) revert ZeroBudget();
        if (provider == address(0)) revert ZeroProvider();

        // The router is both evaluator and hook, which the router enforces.
        jobId = kernel.createJob(provider, address(router), deadline, description, address(router));
        // Bind the dispute policy while the job is still Open. Only the
        // job's client may do this, and this contract is that client.
        router.registerJob(jobId, policy);
        kernel.setBudget(jobId, budget, "");

        hirerOf[jobId] = msg.sender;
        agentOf[jobId] = agentId;
        budgetOf[jobId] = budget;

        token.safeTransferFrom(msg.sender, address(this), budget);
        token.forceApprove(address(kernel), budget);
        kernel.fund(jobId, budget, "");

        emit Hired(jobId, agentId, msg.sender, provider, budget, deadline, specHash);
    }

    /// @notice Forward a settlement to the EvaluatorRouter. Permissionless,
    /// exactly as the router is: anyone may push a decided job to payout.
    /// @dev A rejected job refunds the kernel's client, and this contract is
    /// that client. Any tokens that land here as a result are forwarded to
    /// the person who actually paid, in the same transaction.
    function settle(uint256 jobId, bytes calldata evidence) external nonReentrant {
        address hirer = hirerOf[jobId];
        if (hirer == address(0)) revert UnknownJob();

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
        if (
            status != IAgenticCommerce.JobStatus.Rejected
                && status != IAgenticCommerce.JobStatus.Expired
        ) {
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
