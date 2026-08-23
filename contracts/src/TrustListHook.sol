// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IACPHook} from "./interfaces/IACPHook.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title TrustListHook
/// @notice The ERC-8183 kernel refuses to open a job without a hook that
/// advertises IACPHook over ERC-165. The only hook already deployed on
/// mainnet is the EvaluatorRouter, and it rejects funding for any job it
/// does not itself evaluate, so a job settled by anyone other than the
/// router needs its own hook. This is that hook and it does nothing.
/// @dev Deliberately empty and stateless: it holds no funds, has no owner,
/// and cannot block or alter a job. Its whole purpose is to satisfy the
/// kernel's ERC-165 check.
contract TrustListHook is IACPHook {
    function beforeAction(uint256, bytes4, bytes calldata) external override {}

    function afterAction(uint256, bytes4, bytes calldata) external override {}

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IACPHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
