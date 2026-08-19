// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Subset of the ERC-8183 AgenticCommerce kernel that HireRail uses.
/// Shape taken from the verified deployment's ABI (see contracts/abi/) on
/// BSC mainnet 0xea4daa3100a767e86fded867729ae7446476eba6 and testnet
/// 0xa206c0517b6371c6638cd9e4a42cc9f02a33b0de.
interface IAgenticCommerce {
    enum JobStatus {
        Open,
        Funded,
        Submitted,
        Completed,
        Rejected,
        Expired
    }

    struct Job {
        uint256 id;
        address client;
        address provider;
        address evaluator;
        string description;
        uint256 budget;
        uint256 expiredAt;
        JobStatus status;
        address hook;
        uint256 submittedAt;
        bytes32 deliverable;
    }

    function createJob(
        address provider,
        address evaluator,
        uint256 expiredAt,
        string calldata description,
        address hook
    ) external returns (uint256 jobId);

    function setBudget(uint256 jobId, uint256 amount, bytes calldata optParams) external;

    function fund(uint256 jobId, uint256 expectedBudget, bytes calldata optParams) external;

    function claimRefund(uint256 jobId) external;

    function getJob(uint256 jobId) external view returns (Job memory);

    function jobCounter() external view returns (uint256);

    function paymentToken() external view returns (address);
}
