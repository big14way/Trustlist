// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {HireRail} from "../src/HireRail.sol";
import {TrustListHook} from "../src/TrustListHook.sol";
import {MockKernel, MockPolicy, MockRouter, MockUSD} from "../test/mocks/Mocks.sol";

/// Stands up a complete local hire stack on a plain anvil node for UI
/// development and the end to end suite: a U like token, a kernel and router
/// that enforce the same rules the live ones do, and HireRail on top.
///
/// This is a LOCAL DEVELOPMENT CHAIN, not a substitute for the real thing.
/// HireRailFork.t.sol proves the same HireRail code works against the actual
/// deployed mainnet kernel, router, and policy. The agents shown in the
/// product always come from the real registry index; only the chain is local.
contract DevChain is Script {
    function run() external {
        uint256 key = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(key);

        vm.startBroadcast(key);
        MockUSD usd = new MockUSD();
        MockKernel kernel = new MockKernel(usd);
        // Short dispute window so the whole lifecycle can be walked in a
        // demo. Mainnet's live OptimisticPolicy uses seven days and the UI
        // states the window of whichever chain it is talking to.
        uint64 devDisputeWindow = uint64(vm.envOr("DEV_DISPUTE_WINDOW", uint256(60)));
        MockPolicy policy = new MockPolicy(devDisputeWindow);
        MockRouter router = new MockRouter(kernel, policy);
        TrustListHook hook = new TrustListHook();
        HireRail rail = new HireRail(address(kernel), address(router), address(policy), address(hook));

        // Fund the standard anvil accounts so any of them can hire.
        usd.mint(deployer, 10_000e18);
        usd.mint(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 10_000e18);
        usd.mint(0x70997970C51812dc3A010C7d01b50e0d17dc79C8, 10_000e18);
        vm.stopBroadcast();

        console.log("DEV_TOKEN=%s", address(usd));
        console.log("DEV_KERNEL=%s", address(kernel));
        console.log("DEV_ROUTER=%s", address(router));
        console.log("DEV_POLICY=%s", address(policy));
        console.log("DEV_DISPUTE_WINDOW=%s", devDisputeWindow);
        console.log("DEV_HIRE_RAIL=%s", address(rail));
        console.log("DEV_HOOK=%s", address(hook));
    }
}
