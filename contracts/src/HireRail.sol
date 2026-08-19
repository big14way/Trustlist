// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAgenticCommerce} from "./interfaces/IAgenticCommerce.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title HireRail
/// @notice A thin wrapper over the ERC-8183 AgenticCommerce kernel that
/// turns "open a job, set its budget, fund it" into one transaction tied to
/// an ERC-8004 agent id, with events an indexer can follow. It never holds
/// funds beyond the single hire it is executing and never holds approvals
/// beyond the exact amount mid transaction.
/// @dev Pausable is a hackathon safety valve, owner only, and disclosed in
/// the README. Payment happens in the kernel's own payment token.
contract HireRail is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The ERC-8183 kernel this rail wraps.
    IAgenticCommerce public immutable kernel;
    /// @notice The evaluator passed to every job (the EvaluatorRouter).
    address public immutable evaluator;
    /// @notice The kernel's payment token, cached at deployment.
    IERC20 public immutable token;

    /// @notice The hirer behind each job this rail opened.
    mapping(uint256 => address) public hirerOf;
    /// @notice The ERC-8004 agent id behind each job this rail opened.
    mapping(uint256 => uint256) public agentOf;

    event Hired(
        uint256 indexed jobId,
        uint256 indexed agentId,
        address indexed hirer,
        address provider,
        uint256 budget,
        uint64 deadline,
        bytes32 specHash
    );
    event Reclaimed(uint256 indexed jobId, address indexed hirer, uint256 refunded);

    error DeadlineInPast();
    error ZeroBudget();
    error ZeroProvider();
    error NotHirer();
    error NothingToRefund();

    constructor(address kernel_, address evaluator_) Ownable(msg.sender) {
        kernel = IAgenticCommerce(kernel_);
        evaluator = evaluator_;
        token = IERC20(IAgenticCommerce(kernel_).paymentToken());
    }

    /// @notice Open, budget, and fund an ERC-8183 job in one transaction.
    /// Pulls exactly `budget` of the kernel's payment token from the caller.
    /// @param agentId The ERC-8004 agent id being hired, for indexing.
    /// @param provider The address that will deliver the work.
    /// @param budget Exact amount escrowed, pulled from the caller.
    /// @param deadline Unix time after which the job expires and the escrow
    /// can be reclaimed.
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

        jobId = kernel.createJob(provider, evaluator, deadline, description, address(0));
        kernel.setBudget(jobId, budget, "");

        hirerOf[jobId] = msg.sender;
        agentOf[jobId] = agentId;

        token.safeTransferFrom(msg.sender, address(this), budget);
        token.forceApprove(address(kernel), budget);
        kernel.fund(jobId, budget, "");

        emit Hired(jobId, agentId, msg.sender, provider, budget, deadline, specHash);
    }

    /// @notice Reclaim the escrow of an expired job this rail opened and
    /// forward it to the original hirer. Callable by anyone; funds only ever
    /// move to the recorded hirer.
    function reclaim(uint256 jobId) external nonReentrant {
        address hirer = hirerOf[jobId];
        if (hirer == address(0)) revert NotHirer();
        uint256 before = token.balanceOf(address(this));
        kernel.claimRefund(jobId);
        uint256 refunded = token.balanceOf(address(this)) - before;
        if (refunded == 0) revert NothingToRefund();
        token.safeTransfer(hirer, refunded);
        emit Reclaimed(jobId, hirer, refunded);
    }

    /// @notice Hackathon safety valve, owner only, disclosed in the README.
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
