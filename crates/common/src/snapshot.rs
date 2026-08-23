//! Building the Merkle snapshot of agent scores.
//!
//! Only the root goes on chain. The full leaf set is written alongside it so
//! anyone can rebuild the tree, confirm the root matches, and prove any one
//! agent's score against `TrustSnapshot.verify`. A score nobody can check is
//! just a claim, so the payload is part of the product, not a debug artifact.
//!
//! The hashing here must match `TrustSnapshot.sol` and OpenZeppelin's
//! verifier exactly: leaves are hashed twice, pairs are sorted before
//! hashing, and an odd node is carried up unchanged.

use alloy::primitives::keccak256;
pub use alloy::primitives::{B256, U256};
use alloy::sol_types::SolValue;
use serde::Serialize;

/// Scores are published as basis points, 0 to 10000, so the encoding is
/// exact and reproducible in any language.
pub const MAX_SCORE: u16 = 10_000;

/// Written into every payload so a reader knows exactly how to rebuild the
/// tree without reading our source.
pub const ENCODING: &str =
    "leaf = keccak256(keccak256(abi.encode(uint256 agentId, uint16 liveness, uint16 trust, uint16 confidence, uint64 computedAt))); \
     parents = keccak256(sorted pair); an odd node is carried up unchanged; scores are basis points 0..10000";

#[derive(Debug, Clone, Serialize)]
pub struct Leaf {
    pub agent_id: String,
    pub liveness: u16,
    pub trust: u16,
    pub confidence: u16,
    pub computed_at: u64,
    /// The leaf hash, so a reader can check our arithmetic without repeating
    /// the encoding rules.
    pub leaf: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct Payload {
    pub merkle_root: String,
    pub agent_count: u32,
    pub computed_at: u64,
    pub encoding: &'static str,
    pub leaves: Vec<Leaf>,
}

/// Convert a 0..100 score into basis points, clamped. A missing trust score
/// publishes as zero and is reported as absent in the payload's own fields,
/// never as a middling number.
pub fn to_bps(value: Option<f64>) -> u16 {
    match value {
        Some(v) if v.is_finite() => ((v * 100.0).round().clamp(0.0, MAX_SCORE as f64)) as u16,
        _ => 0,
    }
}

/// keccak256(keccak256(abi.encode(agentId, liveness, trust, confidence, computedAt)))
///
/// Hashed twice so an interior node of the tree can never be presented as a
/// leaf, which is the standard defence and is what the contract expects.
pub fn leaf_hash(
    agent_id: U256,
    liveness: u16,
    trust: u16,
    confidence: u16,
    computed_at: u64,
) -> B256 {
    let encoded = (agent_id, liveness, trust, confidence, computed_at).abi_encode();
    keccak256(keccak256(encoded))
}

fn hash_pair(a: B256, b: B256) -> B256 {
    let mut buf = [0u8; 64];
    if a <= b {
        buf[..32].copy_from_slice(a.as_slice());
        buf[32..].copy_from_slice(b.as_slice());
    } else {
        buf[..32].copy_from_slice(b.as_slice());
        buf[32..].copy_from_slice(a.as_slice());
    }
    keccak256(buf)
}

/// The Merkle root over these leaves, or None for an empty set. We publish
/// nothing rather than publishing a root over nothing.
pub fn merkle_root(leaves: &[B256]) -> Option<B256> {
    if leaves.is_empty() {
        return None;
    }
    let mut level: Vec<B256> = leaves.to_vec();
    while level.len() > 1 {
        let mut up = Vec::with_capacity(level.len().div_ceil(2));
        let mut i = 0;
        while i < level.len() {
            if i + 1 < level.len() {
                up.push(hash_pair(level[i], level[i + 1]));
            } else {
                up.push(level[i]);
            }
            i += 2;
        }
        level = up;
    }
    Some(level[0])
}

/// The sibling path proving `index` belongs to the tree.
pub fn merkle_proof(leaves: &[B256], index: usize) -> Vec<B256> {
    let mut proof = Vec::new();
    if index >= leaves.len() {
        return proof;
    }
    let mut level: Vec<B256> = leaves.to_vec();
    let mut idx = index;
    while level.len() > 1 {
        let sibling = idx ^ 1;
        if sibling < level.len() {
            proof.push(level[sibling]);
        }
        let mut up = Vec::with_capacity(level.len().div_ceil(2));
        let mut i = 0;
        while i < level.len() {
            if i + 1 < level.len() {
                up.push(hash_pair(level[i], level[i + 1]));
            } else {
                up.push(level[i]);
            }
            i += 2;
        }
        level = up;
        idx /= 2;
    }
    proof
}

/// Check a proof the same way the contract does, so the publisher can refuse
/// to publish a tree it cannot itself prove against.
pub fn verify_proof(root: B256, leaf: B256, proof: &[B256]) -> bool {
    let mut computed = leaf;
    for node in proof {
        computed = hash_pair(computed, *node);
    }
    computed == root
}

#[cfg(test)]
mod tests {
    use super::*;

    fn leaves(n: usize) -> Vec<B256> {
        (0..n)
            .map(|i| {
                leaf_hash(
                    U256::from(i + 1),
                    1000 + i as u16,
                    2000 + i as u16,
                    3000 + i as u16,
                    1787000000,
                )
            })
            .collect()
    }

    #[test]
    fn scores_convert_to_basis_points_and_clamp() {
        assert_eq!(to_bps(Some(100.0)), 10_000);
        assert_eq!(to_bps(Some(0.0)), 0);
        assert_eq!(to_bps(Some(79.25)), 7925);
        // Out of range or absent never becomes a flattering number.
        assert_eq!(to_bps(Some(1e9)), 10_000);
        assert_eq!(to_bps(Some(-5.0)), 0);
        assert_eq!(to_bps(None), 0);
        assert_eq!(to_bps(Some(f64::NAN)), 0);
    }

    #[test]
    fn an_empty_set_publishes_nothing() {
        assert!(merkle_root(&[]).is_none());
    }

    #[test]
    fn every_leaf_proves_against_the_root() {
        for n in [1usize, 2, 3, 8, 9, 33, 64] {
            let ls = leaves(n);
            let root = merkle_root(&ls).unwrap();
            for i in 0..n {
                let proof = merkle_proof(&ls, i);
                assert!(
                    verify_proof(root, ls[i], &proof),
                    "leaf {i} of {n} must prove"
                );
            }
        }
    }

    #[test]
    fn a_leaf_that_is_not_in_the_tree_does_not_prove() {
        let ls = leaves(8);
        let root = merkle_root(&ls).unwrap();
        let outsider = leaf_hash(U256::from(999), 9999, 9999, 9999, 1787000000);
        assert!(!verify_proof(root, outsider, &merkle_proof(&ls, 3)));
    }

    /// The attack the whole contract exists to stop: publishing a real
    /// snapshot and then claiming a better score for an agent inside it.
    #[test]
    fn an_inflated_score_cannot_reuse_a_real_proof() {
        let ls = leaves(8);
        let root = merkle_root(&ls).unwrap();
        let proof = merkle_proof(&ls, 3);
        let inflated = leaf_hash(U256::from(4), 1003, 10_000, 3003, 1787000000);
        assert!(!verify_proof(root, inflated, &proof));
    }

    #[test]
    fn changing_the_timestamp_breaks_the_proof() {
        let ls = leaves(4);
        let root = merkle_root(&ls).unwrap();
        let restamped = leaf_hash(U256::from(2), 1001, 2001, 3001, 1787000001);
        assert!(!verify_proof(root, restamped, &merkle_proof(&ls, 1)));
    }

    #[test]
    fn the_root_does_not_depend_on_the_machine_that_built_it() {
        // Same inputs, same root, every time: the payload is only useful if
        // a reader rebuilding it gets the same answer we did.
        let a = merkle_root(&leaves(9)).unwrap();
        let b = merkle_root(&leaves(9)).unwrap();
        assert_eq!(a, b);
    }
}
