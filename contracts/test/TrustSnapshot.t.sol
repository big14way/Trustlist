// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TrustSnapshot} from "../src/TrustSnapshot.sol";
import {Merkle} from "./mocks/Merkle.sol";

contract TrustSnapshotTest is Test {
    TrustSnapshot snap;
    Merkle merkle;

    address owner = makeAddr("owner");
    address publisher = makeAddr("publisher");
    address stranger = makeAddr("stranger");

    function setUp() public {
        snap = new TrustSnapshot(owner);
        merkle = new Merkle();
    }

    function leaves(uint256 n, uint64 at) internal view returns (bytes32[] memory out) {
        out = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            out[i] = snap.leaf(i + 1, uint16(1000 + i), uint16(2000 + i), uint16(3000 + i), at);
        }
    }

    // -----------------------------------------------------------------
    // Publishing
    // -----------------------------------------------------------------

    function test_the_owner_can_publish_and_history_is_append_only() public {
        vm.startPrank(owner);
        uint256 first = snap.publish(bytes32(uint256(1)), 10, 1000, "ipfs://a");
        uint256 second = snap.publish(bytes32(uint256(2)), 20, 2000, "ipfs://b");
        vm.stopPrank();

        assertEq(first, 0);
        assertEq(second, 1);
        assertEq(snap.snapshotCount(), 2);
        // The earlier snapshot is untouched by the later one.
        (bytes32 root0,,,) = snap.snapshots(0);
        assertEq(root0, bytes32(uint256(1)), "published history cannot be rewritten");
        assertEq(snap.latest().merkleRoot, bytes32(uint256(2)));
    }

    function test_a_stranger_cannot_publish() public {
        vm.prank(stranger);
        vm.expectRevert(TrustSnapshot.NotPublisher.selector);
        snap.publish(bytes32(uint256(1)), 1, 1, "x");
    }

    function test_publishers_can_be_added_and_revoked_by_the_owner_only() public {
        vm.prank(stranger);
        vm.expectRevert();
        snap.setPublisher(publisher, true);

        vm.prank(owner);
        snap.setPublisher(publisher, true);
        vm.prank(publisher);
        snap.publish(bytes32(uint256(7)), 1, 1, "x");

        // Revoking a compromised key stops it immediately.
        vm.prank(owner);
        snap.setPublisher(publisher, false);
        vm.prank(publisher);
        vm.expectRevert(TrustSnapshot.NotPublisher.selector);
        snap.publish(bytes32(uint256(8)), 1, 1, "x");
    }

    function test_an_empty_root_is_refused() public {
        vm.prank(owner);
        vm.expectRevert(TrustSnapshot.EmptyRoot.selector);
        snap.publish(bytes32(0), 1, 1, "x");
    }

    function test_latest_reverts_before_anything_is_published() public {
        vm.expectRevert(TrustSnapshot.NoSnapshots.selector);
        snap.latest();
    }

    // -----------------------------------------------------------------
    // Proving a score
    // -----------------------------------------------------------------

    function test_a_published_score_can_be_proved_on_chain() public {
        uint64 at = 1787000000;
        bytes32[] memory ls = leaves(8, at);
        bytes32 root = merkle.root(ls);
        vm.prank(owner);
        snap.publish(root, 8, at, "https://trustlist.example/snapshot/0.json");

        for (uint256 i = 0; i < 8; i++) {
            bytes32[] memory proof = merkle.proof(ls, i);
            assertTrue(
                snap.verify(0, i + 1, uint16(1000 + i), uint16(2000 + i), uint16(3000 + i), at, proof),
                "every agent in the tree must be provable"
            );
        }
    }

    function test_a_score_that_was_not_published_cannot_be_proved() public {
        uint64 at = 1787000000;
        bytes32[] memory ls = leaves(8, at);
        bytes32 root = merkle.root(ls);
        bytes32[] memory proof = merkle.proof(ls, 3);
        vm.prank(owner);
        snap.publish(root, 8, at, "x");

        // Same agent, flattering trust score. This is the attack the whole
        // contract exists to make impossible.
        assertFalse(snap.verify(0, 4, 1003, 9999, 3003, at, proof), "an inflated score must not verify");
        // Right scores, wrong agent.
        assertFalse(snap.verify(0, 99, 1003, 2003, 3003, at, proof), "a swapped agent must not verify");
        // Right everything, wrong timestamp.
        assertFalse(snap.verify(0, 4, 1003, 2003, 3003, at + 1, proof), "a restamped score must not verify");
    }

    function test_a_proof_from_one_snapshot_does_not_work_on_another() public {
        uint64 at = 1787000000;
        bytes32[] memory a = leaves(8, at);
        bytes32[] memory b = leaves(8, at + 86400);
        bytes32 rootA = merkle.root(a);
        bytes32 rootB = merkle.root(b);
        bytes32[] memory proof = merkle.proof(a, 2);
        vm.startPrank(owner);
        snap.publish(rootA, 8, at, "a");
        snap.publish(rootB, 8, at + 86400, "b");
        vm.stopPrank();
        assertTrue(snap.verify(0, 3, 1002, 2002, 3002, at, proof));
        assertFalse(snap.verify(1, 3, 1002, 2002, 3002, at, proof), "yesterday's proof is not today's");
    }

    function test_verifying_against_a_snapshot_that_does_not_exist_reverts() public {
        bytes32[] memory proof = new bytes32[](0);
        vm.expectRevert(TrustSnapshot.UnknownSnapshot.selector);
        snap.verify(0, 1, 1, 1, 1, 1, proof);
    }

    function test_scores_beyond_full_marks_are_refused() public {
        vm.expectRevert(TrustSnapshot.ScoreOutOfRange.selector);
        snap.leaf(1, 10_001, 0, 0, 0);
        vm.expectRevert(TrustSnapshot.ScoreOutOfRange.selector);
        snap.leaf(1, 0, 10_001, 0, 0);
        vm.expectRevert(TrustSnapshot.ScoreOutOfRange.selector);
        snap.leaf(1, 0, 0, 10_001, 0);
    }

    function test_a_single_agent_tree_still_proves() public {
        uint64 at = 1787000000;
        bytes32[] memory ls = leaves(1, at);
        bytes32 root = merkle.root(ls);
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(owner);
        snap.publish(root, 1, at, "x");
        assertTrue(snap.verify(0, 1, 1000, 2000, 3000, at, proof));
    }

    // -----------------------------------------------------------------
    // Cross language agreement
    // -----------------------------------------------------------------

    /// The publisher builds the tree in Rust and this contract verifies it in
    /// Solidity. If the two ever disagree on encoding, hashing order, or how
    /// an odd node is carried up, every published proof breaks silently. So
    /// the values below are pinned from the Rust implementation
    /// (crates/trust/examples/print_root.rs) for a fixed input set. If this
    /// test fails, one of the two sides has drifted and no snapshot can be
    /// trusted until it is fixed.
    function test_the_rust_publisher_and_this_contract_agree() public {
        uint64 at = 1787000000;

        assertEq(
            snap.leaf(1, 1000, 2000, 3000, at),
            0x645bf0f34344e882148472822530c0cf444318dbf29e79a0470db94802f9a926,
            "leaf encoding drifted from the publisher"
        );
        assertEq(
            snap.leaf(4, 1003, 2003, 3003, at),
            0x369241a40f366fe0fb1d0e42bf64f03ac38b5c65988b642821ca13bf2edc5f43,
            "leaf encoding drifted from the publisher"
        );

        bytes32 rustRoot = 0xd6bf1147f97f74082dada12a4750132d9ccb66a7a6c68a776c17421c537eddb7;
        assertEq(merkle.root(leaves(8, at)), rustRoot, "tree construction drifted from the publisher");

        // And a proof built by the Rust side verifies here.
        bytes32[] memory rustProof = new bytes32[](3);
        rustProof[0] = 0x126dc63600426337e96f46346df8f6148e8c4e677371c8cedb123359e7b8d985;
        rustProof[1] = 0xea2579e875072e69558138d99eb1c6894a962683ba31208ce31c3c010e8427ce;
        rustProof[2] = 0x61547d1699bc85f2346e6c975fd10106556f9da4e2b7c11db679f5fa3edf556d;

        vm.prank(owner);
        snap.publish(rustRoot, 8, at, "pinned");
        assertTrue(
            snap.verify(0, 4, 1003, 2003, 3003, at, rustProof), "a proof produced by the publisher must verify on chain"
        );
    }

    // -----------------------------------------------------------------
    // Fuzz
    // -----------------------------------------------------------------

    /// Whatever the scores, an agent that was published proves and a changed
    /// score does not.
    function testFuzz_published_scores_prove_and_altered_ones_do_not(
        uint16 liveness,
        uint16 trust,
        uint16 confidence,
        uint64 at,
        uint8 index
    ) public {
        liveness = uint16(bound(liveness, 0, 10_000));
        trust = uint16(bound(trust, 0, 10_000));
        confidence = uint16(bound(confidence, 0, 10_000));
        uint256 i = bound(index, 0, 7);

        bytes32[] memory ls = new bytes32[](8);
        for (uint256 k = 0; k < 8; k++) {
            ls[k] = snap.leaf(k + 1, liveness, trust, confidence, at);
        }
        bytes32 root = merkle.root(ls);
        bytes32[] memory proof = merkle.proof(ls, i);
        vm.prank(owner);
        snap.publish(root, 8, at, "x");

        assertTrue(snap.verify(0, i + 1, liveness, trust, confidence, at, proof));

        if (trust < 10_000) {
            assertFalse(
                snap.verify(0, i + 1, liveness, trust + 1, confidence, at, proof),
                "nudging a score by one must break the proof"
            );
        }
    }

    function testFuzz_any_tree_size_proves_every_member(uint8 size, uint8 index) public {
        uint256 n = bound(size, 1, 64);
        uint256 i = bound(index, 0, n - 1);
        uint64 at = 1787000000;

        bytes32[] memory ls = leaves(n, at);
        bytes32 root = merkle.root(ls);
        bytes32[] memory proof = merkle.proof(ls, i);
        vm.prank(owner);
        snap.publish(root, uint32(n), at, "x");
        assertTrue(
            snap.verify(0, i + 1, uint16(1000 + i), uint16(2000 + i), uint16(3000 + i), at, proof),
            "proofs must hold at every tree size, including odd ones"
        );
    }
}
