// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAgenticCommerce} from "../../src/interfaces/IAgenticCommerce.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// Local stand ins for the live ERC-8183 stack, matching the real ABI and
/// the real access rules so unit tests and the local dev chain behave the
/// way mainnet does. HireRailFork.t.sol proves the same HireRail code works
/// against the actual deployed contracts.
contract MockUSD is ERC20 {
    constructor() ERC20("United Stables", "U") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockKernel {
    MockUSD public immutable usd;
    uint256 public jobCounter;

    struct J {
        address client;
        address provider;
        address evaluator;
        address hook;
        uint256 budget;
        uint256 expiredAt;
        uint256 submittedAt;
        bytes32 deliverable;
        IAgenticCommerce.JobStatus status;
    }

    mapping(uint256 => J) public jobsById;

    error NotClient();
    error NotProvider();
    error NotEvaluator();
    error WrongStatus();

    constructor(MockUSD usd_) {
        usd = usd_;
    }

    function paymentToken() external view returns (address) {
        return address(usd);
    }

    function createJob(address provider, address evaluator, uint256 expiredAt, string calldata, address hook)
        external
        returns (uint256 jobId)
    {
        jobId = ++jobCounter;
        J storage j = jobsById[jobId];
        j.client = msg.sender;
        j.provider = provider;
        j.evaluator = evaluator;
        j.hook = hook;
        j.expiredAt = expiredAt;
        j.status = IAgenticCommerce.JobStatus.Open;
    }

    function setBudget(uint256 jobId, uint256 amount, bytes calldata) external {
        if (jobsById[jobId].client != msg.sender) revert NotClient();
        jobsById[jobId].budget = amount;
    }

    function fund(uint256 jobId, uint256 expectedBudget, bytes calldata) external {
        J storage j = jobsById[jobId];
        if (j.budget != expectedBudget) revert WrongStatus();
        if (j.status != IAgenticCommerce.JobStatus.Open) revert WrongStatus();
        usd.transferFrom(msg.sender, address(this), expectedBudget);
        j.status = IAgenticCommerce.JobStatus.Funded;
    }

    /// The provider delivers. Recording the time starts the dispute window.
    function submit(uint256 jobId, bytes32 deliverable, bytes calldata) external {
        J storage j = jobsById[jobId];
        if (j.provider != msg.sender) revert NotProvider();
        if (j.status != IAgenticCommerce.JobStatus.Funded) revert WrongStatus();
        j.status = IAgenticCommerce.JobStatus.Submitted;
        j.submittedAt = block.timestamp;
        j.deliverable = deliverable;
    }

    /// Only the evaluator may release escrow, which is what makes the
    /// evaluator choice the whole trust question.
    function complete(uint256 jobId, bytes32, bytes calldata) external {
        J storage j = jobsById[jobId];
        if (j.evaluator != msg.sender) revert NotEvaluator();
        if (j.status != IAgenticCommerce.JobStatus.Submitted) revert WrongStatus();
        j.status = IAgenticCommerce.JobStatus.Completed;
        uint256 amount = j.budget;
        j.budget = 0;
        usd.transfer(j.provider, amount);
    }

    function reject(uint256 jobId, bytes32, bytes calldata) external {
        J storage j = jobsById[jobId];
        if (j.evaluator != msg.sender) revert NotEvaluator();
        if (j.status != IAgenticCommerce.JobStatus.Submitted) revert WrongStatus();
        j.status = IAgenticCommerce.JobStatus.Rejected;
        uint256 amount = j.budget;
        j.budget = 0;
        usd.transfer(j.client, amount);
    }

    function claimRefund(uint256 jobId) external {
        J storage j = jobsById[jobId];
        if (j.client != msg.sender) revert NotClient();
        if (j.status != IAgenticCommerce.JobStatus.Expired) revert WrongStatus();
        uint256 amount = j.budget;
        j.budget = 0;
        usd.transfer(j.client, amount);
    }

    function markExpiredBy(uint256 jobId) external {
        J storage j = jobsById[jobId];
        if (block.timestamp <= j.expiredAt) revert WrongStatus();
        if (j.status != IAgenticCommerce.JobStatus.Funded) revert WrongStatus();
        j.status = IAgenticCommerce.JobStatus.Expired;
    }

    function getJob(uint256 jobId) external view returns (IAgenticCommerce.Job memory job) {
        J storage j = jobsById[jobId];
        job.id = jobId;
        job.client = j.client;
        job.provider = j.provider;
        job.evaluator = j.evaluator;
        job.hook = j.hook;
        job.budget = j.budget;
        job.expiredAt = j.expiredAt;
        job.status = j.status;
        job.submittedAt = j.submittedAt;
        job.deliverable = j.deliverable;
    }
}

/// Mirrors OptimisticPolicy: silence past the dispute window is approval.
/// The live mainnet policy uses a seven day window; the dev chain uses a
/// short one so the whole lifecycle can be walked in a demo. The UI always
/// states the window of the chain it is actually talking to.
contract MockPolicy {
    uint64 public disputeWindow;
    mapping(uint256 => bool) public disputed;

    constructor(uint64 disputeWindow_) {
        disputeWindow = disputeWindow_;
    }

    function dispute(uint256 jobId) external {
        disputed[jobId] = true;
    }

    function decided(uint256 submittedAt) external view returns (bool) {
        return submittedAt != 0 && block.timestamp >= submittedAt + disputeWindow;
    }
}

contract MockRouter {
    MockKernel public immutable kernel;
    MockPolicy public immutable policy;
    mapping(uint256 => address) public jobPolicy;
    mapping(address => bool) public policyWhitelist;

    error RouterNotEvaluator();
    error RouterNotHook();
    error NotJobClient();
    error PolicyNotWhitelisted();
    error PolicyNotSet();
    error NotDecided();
    error NotExpired();

    constructor(MockKernel kernel_, MockPolicy policy_) {
        kernel = kernel_;
        policy = policy_;
        policyWhitelist[address(policy_)] = true;
    }

    function registerJob(uint256 jobId, address policy_) external {
        IAgenticCommerce.Job memory j = kernel.getJob(jobId);
        if (j.evaluator != address(this)) revert RouterNotEvaluator();
        if (j.hook != address(this)) revert RouterNotHook();
        if (j.client != msg.sender) revert NotJobClient();
        if (!policyWhitelist[policy_]) revert PolicyNotWhitelisted();
        jobPolicy[jobId] = policy_;
    }

    /// Permissionless: once the policy has decided, anyone may push the
    /// payout through. Nobody has to ask us for their money.
    function settle(uint256 jobId, bytes calldata) external {
        if (jobPolicy[jobId] == address(0)) revert PolicyNotSet();
        IAgenticCommerce.Job memory j = kernel.getJob(jobId);
        if (!policy.decided(j.submittedAt)) revert NotDecided();
        if (policy.disputed(jobId)) {
            kernel.reject(jobId, bytes32(0), "");
        } else {
            kernel.complete(jobId, bytes32(0), "");
        }
    }

    function markExpired(uint256 jobId) external {
        kernel.markExpiredBy(jobId);
    }
}
