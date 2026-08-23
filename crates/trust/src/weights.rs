//! Reviewer independence. SPEC.md Section 13 step 1.
//!
//! Every address that has left feedback starts at weight 1.0 and is
//! multiplied down by each signal that it is not an independent voice. We
//! downweight rather than delete, and the floor is 0.02 rather than zero, so
//! the product can always show "we saw 412 reviews and counted 19" instead
//! of quietly dropping evidence.
//!
//! Two of these signals are the ones that actually catch the farm operating
//! on BSC today: a shared funder, and a group of addresses that reviews the
//! same agents together. The burst detector the spec anticipated barely
//! fires, because the real farm is patient and drips reviews over weeks.

use petgraph::unionfind::UnionFind;
use std::collections::HashMap;

// Every threshold and penalty lives in common::methodology, which the API
// publishes at /v1/methodology. There is exactly one copy of each number, so
// the rules a reader is shown are the rules that ran.
use common::methodology as m;
pub use common::methodology::{
    CLUSTER_LARGE, COREVIEW_PEERS, MIN_SHARED_AGENTS, WEIGHT_FLOOR as FLOOR,
};

#[derive(Debug, Clone)]
pub struct ReviewerFacts {
    pub reviewer: Vec<u8>,
    pub feedback_count: i64,
    pub revoked_count: i64,
    /// Scaled 0..100 scores this reviewer has given.
    pub min_score: f64,
    pub max_score: f64,
    /// Seconds between the reviewer's first funding and its first feedback.
    pub seconds_funded_before_first_review: Option<i64>,
    /// Transfers out of this address, a proxy for doing anything else.
    pub outbound_count: i32,
    pub funder: Option<Vec<u8>>,
}

#[derive(Debug, Clone)]
pub struct ReviewerWeight {
    pub reviewer: Vec<u8>,
    pub weight: f64,
    pub cluster_id: Option<i64>,
    pub flags: Vec<String>,
}

/// Group reviewers into clusters over shared funding, using union find so
/// that A funded by X and B funded by X land in one component even when the
/// funder itself never reviewed anything.
pub fn cluster_by_funding(facts: &[ReviewerFacts]) -> HashMap<Vec<u8>, i64> {
    let mut index: HashMap<Vec<u8>, usize> = HashMap::new();
    for (i, f) in facts.iter().enumerate() {
        index.insert(f.reviewer.clone(), i);
    }
    // One extra node per distinct funder so reviewers join through it.
    let mut funder_node: HashMap<Vec<u8>, usize> = HashMap::new();
    let mut next = facts.len();
    for f in facts {
        if let Some(funder) = &f.funder {
            funder_node.entry(funder.clone()).or_insert_with(|| {
                let n = next;
                next += 1;
                n
            });
        }
    }

    let mut uf = UnionFind::<usize>::new(next.max(1));
    for f in facts {
        if let (Some(funder), Some(&i)) = (&f.funder, index.get(&f.reviewer)) {
            if let Some(&fnode) = funder_node.get(funder) {
                uf.union(i, fnode);
            }
        }
    }

    let mut cluster_of: HashMap<Vec<u8>, i64> = HashMap::new();
    for f in facts {
        if let Some(&i) = index.get(&f.reviewer) {
            cluster_of.insert(f.reviewer.clone(), uf.find(i) as i64);
        }
    }
    cluster_of
}

/// How many reviewers sit in each cluster.
pub fn cluster_sizes(cluster_of: &HashMap<Vec<u8>, i64>) -> HashMap<i64, usize> {
    let mut sizes: HashMap<i64, usize> = HashMap::new();
    for id in cluster_of.values() {
        *sizes.entry(*id).or_insert(0) += 1;
    }
    sizes
}

pub fn compute(
    facts: &[ReviewerFacts],
    cluster_of: &HashMap<Vec<u8>, i64>,
    sizes: &HashMap<i64, usize>,
    coreview_peers: &HashMap<Vec<u8>, i64>,
    reciprocal: &std::collections::HashSet<Vec<u8>>,
) -> Vec<ReviewerWeight> {
    facts
        .iter()
        .map(|f| {
            let mut weight = 1.0_f64;
            let mut flags: Vec<String> = Vec::new();
            let cluster_id = cluster_of.get(&f.reviewer).copied();
            let cluster_size = cluster_id
                .and_then(|id| sizes.get(&id))
                .copied()
                .unwrap_or(1);

            // Somebody paid for a crowd of reviewers. This is the signal that
            // actually catches the farm running on BSC today.
            if cluster_size >= CLUSTER_LARGE {
                weight *= m::P_FUNDING_CLUSTER;
                flags.push("funding_cluster".into());
            } else if cluster_size > 1 {
                weight *= m::P_SHARED_FUNDER;
                flags.push("shared_funder".into());
            }

            // Reviews the same agents as several other reviewers, over and
            // over. A patient farm looks exactly like this.
            if coreview_peers.get(&f.reviewer).copied().unwrap_or(0) >= COREVIEW_PEERS {
                weight *= m::P_COREVIEW_RING;
                flags.push("coreview_ring".into());
            }

            // One review and no other business on chain.
            if f.feedback_count == 1 && f.outbound_count < 5 {
                weight *= m::P_ONE_SHOT;
                flags.push("one_shot".into());
            } else if f.outbound_count < 5 {
                weight *= m::P_NO_OTHER_ACTIVITY;
                flags.push("no_other_activity".into());
            }

            // Never says anything but the best.
            if f.feedback_count >= 3 && (f.max_score - f.min_score).abs() < f64::EPSILON {
                weight *= m::P_SINGLE_VALUE_ONLY;
                flags.push("single_value_only".into());
            }

            // Funded and reviewing within the week.
            if let Some(secs) = f.seconds_funded_before_first_review {
                if (0..m::FRESH_WINDOW_SECS).contains(&secs) {
                    weight *= m::P_FRESH_ADDRESS;
                    flags.push("fresh_address".into());
                }
            }

            // Rates an agent whose owner rates an agent it owns.
            if reciprocal.contains(&f.reviewer) {
                weight *= m::P_RECIPROCAL;
                flags.push("reciprocal".into());
            }

            // Writes feedback and then takes it back.
            if f.feedback_count >= 3 && f.revoked_count * 2 >= f.feedback_count {
                weight *= m::P_HIGH_REVOCATION;
                flags.push("high_revocation".into());
            }

            ReviewerWeight {
                reviewer: f.reviewer.clone(),
                weight: weight.max(FLOOR),
                cluster_id,
                flags,
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    fn facts(id: u8, count: i64, funder: Option<u8>, outbound: i32) -> ReviewerFacts {
        ReviewerFacts {
            reviewer: vec![id],
            feedback_count: count,
            revoked_count: 0,
            min_score: 50.0,
            max_score: 90.0,
            seconds_funded_before_first_review: None,
            outbound_count: outbound,
            funder: funder.map(|f| vec![f]),
        }
    }

    /// The synthetic dataset the spec asks for: one honest reviewer, a farm
    /// sharing a funder, and a pair sharing a different funder.
    fn scenario() -> Vec<ReviewerFacts> {
        let mut v = vec![facts(1, 12, Some(200), 40)];
        for id in 10..16u8 {
            v.push(facts(id, 30, Some(201), 30));
        }
        v.push(facts(20, 5, Some(202), 30));
        v.push(facts(21, 5, Some(202), 30));
        v
    }

    #[test]
    fn shared_funding_collapses_into_one_cluster() {
        let f = scenario();
        let clusters = cluster_by_funding(&f);
        let sizes = cluster_sizes(&clusters);
        let farm = clusters.get(&vec![10u8]).copied().unwrap();
        assert_eq!(
            sizes.get(&farm).copied().unwrap(),
            6,
            "the farm is one cluster"
        );
        let honest = clusters.get(&vec![1u8]).copied().unwrap();
        assert_eq!(
            sizes.get(&honest).copied().unwrap(),
            1,
            "the honest one stands alone"
        );
        assert_ne!(farm, honest, "and they are not the same cluster");
    }

    #[test]
    fn the_farm_is_weighted_down_and_the_honest_reviewer_is_not() {
        let f = scenario();
        let clusters = cluster_by_funding(&f);
        let sizes = cluster_sizes(&clusters);
        let weights = compute(&f, &clusters, &sizes, &HashMap::new(), &HashSet::new());
        let by = |id: u8| {
            weights
                .iter()
                .find(|w| w.reviewer == vec![id])
                .unwrap()
                .clone()
        };

        let honest = by(1);
        assert_eq!(
            honest.weight, 1.0,
            "an independent reviewer keeps full weight"
        );
        assert!(honest.flags.is_empty());

        let farmer = by(10);
        assert_eq!(farmer.weight, 0.25, "six addresses on one funder");
        assert!(farmer.flags.contains(&"funding_cluster".to_string()));

        let pair = by(20);
        assert_eq!(pair.weight, 0.5, "a pair is suspicious, not damning");
        assert!(pair.flags.contains(&"shared_funder".to_string()));
    }

    #[test]
    fn signals_stack_and_never_reach_zero() {
        let mut f = facts(30, 1, Some(201), 0);
        f.min_score = 100.0;
        f.max_score = 100.0;
        f.seconds_funded_before_first_review = Some(3600);
        let mut all = scenario();
        all.push(f);
        let clusters = cluster_by_funding(&all);
        let sizes = cluster_sizes(&clusters);
        let mut peers = HashMap::new();
        peers.insert(vec![30u8], 9);
        let mut recip = HashSet::new();
        recip.insert(vec![30u8]);
        let weights = compute(&all, &clusters, &sizes, &peers, &recip);
        let w = weights.iter().find(|w| w.reviewer == vec![30u8]).unwrap();
        assert_eq!(
            w.weight, FLOOR,
            "stacked signals land on the floor, not zero"
        );
        assert!(
            w.flags.len() >= 4,
            "and every reason is recorded: {:?}",
            w.flags
        );
    }

    #[test]
    fn a_reviewer_with_no_funder_is_its_own_cluster() {
        let f = vec![facts(1, 5, None, 30), facts(2, 5, None, 30)];
        let clusters = cluster_by_funding(&f);
        let sizes = cluster_sizes(&clusters);
        assert_eq!(sizes.len(), 2, "untraced reviewers are not lumped together");
    }
}
