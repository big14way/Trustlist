// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {HireRail} from "../src/HireRail.sol";
import {TrustListHook} from "../src/TrustListHook.sol";

/// Deploys HireRail against the canonical ERC-8183 stack, picking addresses
/// by chain id. Addresses come from the BNBAgent SDK deployment manifest and
/// were verified on chain (see docs/VERIFICATION.md). A mainnet fork reports
/// chain id 56, so this script also covers local fork runs.
contract Deploy is Script {
    address constant MAINNET_KERNEL = 0xEa4DAa3100A767e86FDed867729ae7446476EBA6;
    address constant MAINNET_ROUTER = 0x51895229E12F9876011789B04f8698af06cCD6DA;
    address constant MAINNET_POLICY = 0x9C01845705b3078Aa2e8cfF7520a6376FD766dE5;

    address constant TESTNET_KERNEL = 0xa206c0517B6371C6638CD9e4a42Cc9f02A33B0DE;
    address constant TESTNET_ROUTER = 0xD7d36D66d2F1B608A0F943f722D27e3744f66F25;
    address constant TESTNET_POLICY = 0xd6a4217588F6B1F5657a92A3e94E6422aD771cEA;

    function addresses() public view returns (address kernel, address router, address policy) {
        if (block.chainid == 56) {
            return (MAINNET_KERNEL, MAINNET_ROUTER, MAINNET_POLICY);
        }
        if (block.chainid == 97) {
            return (TESTNET_KERNEL, TESTNET_ROUTER, TESTNET_POLICY);
        }
        revert("unsupported chain");
    }

    function run() external {
        (address kernel, address router, address policy) = addresses();
        uint256 key = vm.envUint("DEPLOYER_KEY");
        vm.startBroadcast(key);
        TrustListHook hook = new TrustListHook();
        HireRail rail = new HireRail(kernel, router, policy, address(hook));
        vm.stopBroadcast();
        console.log("chain id     ", block.chainid);
        console.log("HireRail     ", address(rail));
        console.log("TrustListHook", address(hook));
        console.log("kernel       ", kernel);
        console.log("router       ", router);
        console.log("policy       ", policy);
        console.log("payment token", address(rail.token()));
    }
}
