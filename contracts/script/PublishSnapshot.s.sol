// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TrustSnapshot} from "../src/TrustSnapshot.sol";

/// Deploy the snapshot register, or publish a root into an existing one.
///
/// The signing key lives in the environment and is only ever used here, never
/// in a long running service. Publishing is deliberate: the trust engine
/// builds and stores a root every cycle, a human decides which one goes on
/// chain.
contract PublishSnapshot is Script {
    function run() external {
        uint256 key = vm.envUint("DEPLOYER_KEY");
        address existing = vm.envOr("TRUST_SNAPSHOT", address(0));

        vm.startBroadcast(key);
        TrustSnapshot snap = existing == address(0) ? new TrustSnapshot(vm.addr(key)) : TrustSnapshot(existing);

        bytes32 root = vm.envBytes32("SNAPSHOT_ROOT");
        uint32 count = uint32(vm.envUint("SNAPSHOT_AGENT_COUNT"));
        uint64 at = uint64(vm.envUint("SNAPSHOT_COMPUTED_AT"));
        string memory uri = vm.envOr("SNAPSHOT_URI", string("/v1/snapshots/latest?payload=true"));

        uint256 id = snap.publish(root, count, at, uri);
        vm.stopBroadcast();

        console.log("TrustSnapshot", address(snap));
        console.log("snapshot id", id);
        console.log("agents", count);
    }
}
