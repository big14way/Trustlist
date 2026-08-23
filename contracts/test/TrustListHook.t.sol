// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TrustListHook} from "../src/TrustListHook.sol";
import {IACPHook} from "../src/interfaces/IACPHook.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract TrustListHookTest is Test {
    TrustListHook hook;

    function setUp() public {
        hook = new TrustListHook();
    }

    /// The kernel refuses any hook that does not answer this exact id, so
    /// this assertion is what makes a direct hire possible at all.
    function test_advertises_the_interface_the_kernel_demands() public view {
        assertTrue(hook.supportsInterface(type(IACPHook).interfaceId), "IACPHook");
        assertTrue(hook.supportsInterface(type(IERC165).interfaceId), "IERC165");
        assertFalse(hook.supportsInterface(0xffffffff), "not a wildcard");
        assertFalse(hook.supportsInterface(0x12345678), "not an arbitrary id");
    }

    /// The hook must never be able to block or alter a job. Anyone may call
    /// it with anything and it does nothing at all.
    function test_callbacks_do_nothing_and_never_revert() public {
        address anyone = makeAddr("anyone");
        vm.startPrank(anyone);
        hook.beforeAction(1, bytes4(0), "");
        hook.afterAction(1, bytes4(0), "");
        hook.beforeAction(type(uint256).max, 0xffffffff, hex"deadbeefcafe");
        hook.afterAction(type(uint256).max, 0xffffffff, hex"deadbeefcafe");
        vm.stopPrank();
    }

    function test_holds_nothing_and_owns_nothing() public view {
        assertEq(address(hook).balance, 0, "holds no native balance");
        // No owner, no admin, no storage: the deployed code is the whole
        // contract and it has no way to hold or move value.
        assertEq(vm.load(address(hook), bytes32(0)), bytes32(0), "no state in slot zero");
    }
}
