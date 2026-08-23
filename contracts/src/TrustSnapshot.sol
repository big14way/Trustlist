// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title TrustSnapshot
/// @notice Publishes periodic score snapshots so anyone can check a TrustList
/// score against the chain instead of taking our word for it.
///
/// Only the Merkle root goes on chain. The full leaf set is published at
/// `payloadURI`, so a reader can rebuild the tree themselves, confirm the
/// root matches, and then prove any single agent's score with `verify`.
/// That is the whole point: a score nobody can check is just a claim.
///
/// @dev Scores are basis point style integers from 0 to 10000 rather than
/// decimals, so the leaf encoding is exact and reproducible in any language.
contract TrustSnapshot is Ownable2Step {
    struct Snapshot {
        bytes32 merkleRoot;
        uint64 computedAt;
        uint32 agentCount;
        string payloadURI;
    }

    /// @notice Every snapshot ever published, oldest first.
    Snapshot[] public snapshots;

    /// @notice Addresses allowed to publish. The publishing key holds a few
    /// dollars of gas and nothing else, and it cannot change scores that are
    /// already published: history is append only.
    mapping(address => bool) public publishers;

    event SnapshotPublished(
        uint256 indexed id, bytes32 merkleRoot, uint32 agentCount, uint64 computedAt, string payloadURI
    );
    event PublisherSet(address indexed publisher, bool allowed);

    error NotPublisher();
    error EmptyRoot();
    error NoSnapshots();
    error UnknownSnapshot();
    error ScoreOutOfRange();

    /// Scores are stored in basis points, so this is the ceiling for each.
    uint16 public constant MAX_SCORE = 10_000;

    constructor(address owner_) Ownable(owner_) {
        publishers[owner_] = true;
        emit PublisherSet(owner_, true);
    }

    modifier onlyPublisher() {
        if (!publishers[msg.sender]) revert NotPublisher();
        _;
    }

    /// @notice Allow or revoke a publishing key.
    function setPublisher(address publisher, bool allowed) external onlyOwner {
        publishers[publisher] = allowed;
        emit PublisherSet(publisher, allowed);
    }

    /// @notice Publish a new snapshot root.
    /// @param merkleRoot Root over the leaves described by `leaf`.
    /// @param agentCount How many agents the tree covers, for display.
    /// @param computedAt When the scores were computed, seconds since epoch.
    /// @param payloadURI Where the full leaf set can be fetched and rebuilt.
    /// @return id The index of the new snapshot.
    function publish(bytes32 merkleRoot, uint32 agentCount, uint64 computedAt, string calldata payloadURI)
        external
        onlyPublisher
        returns (uint256 id)
    {
        if (merkleRoot == bytes32(0)) revert EmptyRoot();
        id = snapshots.length;
        snapshots.push(
            Snapshot({merkleRoot: merkleRoot, computedAt: computedAt, agentCount: agentCount, payloadURI: payloadURI})
        );
        emit SnapshotPublished(id, merkleRoot, agentCount, computedAt, payloadURI);
    }

    /// @notice How many snapshots exist.
    function snapshotCount() external view returns (uint256) {
        return snapshots.length;
    }

    /// @notice The most recent snapshot.
    function latest() external view returns (Snapshot memory) {
        if (snapshots.length == 0) revert NoSnapshots();
        return snapshots[snapshots.length - 1];
    }

    /// @notice The leaf hash for one agent's scores.
    /// @dev Hashed twice, which is the standard defence against an interior
    /// node of the tree being passed off as a leaf. Anyone rebuilding the
    /// tree must do the same.
    function leaf(uint256 agentId, uint16 liveness, uint16 trust, uint16 confidence, uint64 computedAt)
        public
        pure
        returns (bytes32)
    {
        if (liveness > MAX_SCORE || trust > MAX_SCORE || confidence > MAX_SCORE) {
            revert ScoreOutOfRange();
        }
        return keccak256(bytes.concat(keccak256(abi.encode(agentId, liveness, trust, confidence, computedAt))));
    }

    /// @notice Check one agent's scores against a published snapshot.
    /// @return True when these exact values were in the tree we published.
    function verify(
        uint256 snapshotId,
        uint256 agentId,
        uint16 liveness,
        uint16 trust,
        uint16 confidence,
        uint64 computedAt,
        bytes32[] calldata proof
    ) external view returns (bool) {
        if (snapshotId >= snapshots.length) revert UnknownSnapshot();
        return MerkleProof.verifyCalldata(
            proof, snapshots[snapshotId].merkleRoot, leaf(agentId, liveness, trust, confidence, computedAt)
        );
    }
}
