// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {HireRail} from "../src/HireRail.sol";

/// Deploys HireRail on BSC testnet (chain 97) against the canonical
/// ERC-8183 stack from the BNBAgent SDK's deployment manifest:
/// kernel 0xa206c0517b6371c6638cd9e4a42cc9f02a33b0de,
/// router 0xd7d36d66d2f1b608a0f943f722d27e3744f66f25.
contract DeployTestnet is Script {
    address constant KERNEL = 0xa206c0517B6371C6638CD9e4a42Cc9f02A33B0DE;
    address constant ROUTER = 0xD7d36D66d2F1B608A0F943f722D27e3744f66F25;

    function run() external {
        uint256 key = vm.envUint("DEPLOYER_KEY");
        vm.startBroadcast(key);
        HireRail rail = new HireRail(KERNEL, ROUTER);
        vm.stopBroadcast();
        console.log("HireRail deployed at", address(rail));
        console.log("payment token", address(rail.token()));
    }
}
