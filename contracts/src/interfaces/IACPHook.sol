// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice The ERC-8183 kernel's job hook. Shape taken from bnb-chain's
/// apex-contracts, the source the live deployment was compiled from.
/// @dev createJob requires a non zero hook whose ERC-165 answer includes
/// this interface id, or it reverts HookRequired / HookMissingInterface.
interface IACPHook is IERC165 {
    function beforeAction(uint256 jobId, bytes4 selector, bytes calldata data) external;
    function afterAction(uint256 jobId, bytes4 selector, bytes calldata data) external;
}
