// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Subset of the ERC-8183 EvaluatorRouter that HireRail uses.
/// Shape taken from the verified deployment's ABI (contracts/abi/) at
/// mainnet 0x51895229e12f9876011789b04f8698af06ccd6da.
/// @dev The router must be BOTH the job's evaluator and its hook, and the
/// job's client must bind a whitelisted policy while the job is still Open,
/// or the router reverts with RouterNotEvaluator, RouterNotHook, or
/// NotJobClient. Settlement is permissionless once the policy has decided.
interface IEvaluatorRouter {
    function registerJob(uint256 jobId, address policy) external;

    function settle(uint256 jobId, bytes calldata evidence) external;

    function markExpired(uint256 jobId) external;

    function jobPolicy(uint256 jobId) external view returns (address);

    function policyWhitelist(address policy) external view returns (bool);
}
