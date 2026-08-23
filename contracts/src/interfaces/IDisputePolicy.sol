// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice The part of an ERC-8183 settlement policy HireRail needs to know
/// about. OptimisticPolicy on BSC mainnet stores this as an immutable, so a
/// job whose deadline does not outlast the window can never settle: it
/// expires first.
interface IDisputePolicy {
    function disputeWindow() external view returns (uint64);
}
