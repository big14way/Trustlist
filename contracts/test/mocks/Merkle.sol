// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// A plain Merkle tree for tests, matching OpenZeppelin's verifier: pairs are
/// sorted before hashing, and an odd node is carried up unchanged. The
/// publisher script builds trees the same way, so a proof produced off chain
/// verifies on chain.
contract Merkle {
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encode(a, b)) : keccak256(abi.encode(b, a));
    }

    function root(bytes32[] memory leaves) public pure returns (bytes32) {
        require(leaves.length > 0, "empty tree");
        bytes32[] memory level = leaves;
        while (level.length > 1) {
            uint256 next = (level.length + 1) / 2;
            bytes32[] memory up = new bytes32[](next);
            for (uint256 i = 0; i < next; i++) {
                uint256 l = i * 2;
                uint256 r = l + 1;
                up[i] = r < level.length ? _hashPair(level[l], level[r]) : level[l];
            }
            level = up;
        }
        return level[0];
    }

    function proof(bytes32[] memory leaves, uint256 index) public pure returns (bytes32[] memory) {
        require(index < leaves.length, "out of range");
        bytes32[] memory acc = new bytes32[](32);
        uint256 count = 0;
        bytes32[] memory level = leaves;
        uint256 idx = index;

        while (level.length > 1) {
            uint256 sibling = idx ^ 1;
            if (sibling < level.length) {
                acc[count++] = level[sibling];
            }
            uint256 next = (level.length + 1) / 2;
            bytes32[] memory up = new bytes32[](next);
            for (uint256 i = 0; i < next; i++) {
                uint256 l = i * 2;
                uint256 r = l + 1;
                up[i] = r < level.length ? _hashPair(level[l], level[r]) : level[l];
            }
            level = up;
            idx /= 2;
        }

        bytes32[] memory out = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            out[i] = acc[i];
        }
        return out;
    }
}
