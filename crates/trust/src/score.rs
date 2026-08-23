//! Turning weighted feedback into an agent trust score.
//! SPEC.md Section 13 steps 2 and 4, with the normalisation pinned down
//! against what the registry actually contains.

use std::collections::HashMap;

// Shared with the published methodology so the two cannot drift.
pub use common::methodology::PRIOR_M;

/// The least surviving weight we will publish a score from: one full
/// independent voice. Below this the Bayesian result is almost entirely the
/// prior, which is our guess about agents in general rather than evidence
/// about this one. Publishing that as a trust score would be inventing a
/// number, so we report no score and say why. This is the rule that makes
/// "234 reviews, none of them independent" show up as an absence rather
/// than as a respectable looking 79.
pub use common::methodology::MIN_EVIDENCE;

/// The ERC-8004 Reputation Registry stores a signed int128 with a per event
/// decimals field and defines no scale, so scores are not comparable across
/// agents until somebody picks a rule. Ours, published on the methodology
/// page: divide by 10^decimals, clamp into 0..100, and read that as a
/// percentage. Every one of the 29,511 feedback events on BSC today lands
/// inside that range once scaled, so the clamp is a guard rather than a
/// reinterpretation. Negative values mean the worst possible score.
pub fn normalise(value: f64, decimals: i32) -> f64 {
    let scaled = value / 10f64.powi(decimals);
    scaled.clamp(0.0, 100.0) / 100.0
}

#[derive(Debug, Clone)]
pub struct Feedback {
    pub agent_id: String,
    pub reviewer: Vec<u8>,
    pub value: f64,
    pub decimals: i32,
}

#[derive(Debug, Clone)]
pub struct AgentTrust {
    pub agent_id: String,
    /// 0..100, or None when no weighted evidence survives.
    pub trust: Option<f64>,
    /// 0..1. Shown as a band, never hidden.
    pub confidence: f64,
    /// The unweighted average, so the product can show both numbers.
    pub raw_average: f64,
    pub feedback_total: i64,
    /// Effective count after weighting, rounded for display.
    pub feedback_kept: i64,
}

/// Compute trust per agent from weighted feedback.
///
/// The cluster cap is what actually kills a farm. Without it, twenty
/// downweighted addresses still outvote one real reviewer by sheer count.
/// So for each agent we group its reviewers by cluster and let a cluster
/// contribute no more than its single strongest member: a farm speaks once,
/// however many addresses it owns.
pub fn compute(
    feedback: &[Feedback],
    weights: &HashMap<Vec<u8>, f64>,
    clusters: &HashMap<Vec<u8>, i64>,
) -> Vec<AgentTrust> {
    let mut by_agent: HashMap<String, Vec<&Feedback>> = HashMap::new();
    for f in feedback {
        by_agent.entry(f.agent_id.clone()).or_default().push(f);
    }

    // Population mean over weighted evidence, used to shrink thin agents
    // toward what a typical agent looks like rather than toward nothing.
    let mut pop_num = 0.0;
    let mut pop_den = 0.0;
    for f in feedback {
        let w = weights.get(&f.reviewer).copied().unwrap_or(1.0);
        pop_num += w * normalise(f.value, f.decimals);
        pop_den += w;
    }
    let mu = if pop_den > 0.0 {
        pop_num / pop_den
    } else {
        0.5
    };

    let mut out = Vec::with_capacity(by_agent.len());
    for (agent_id, items) in by_agent {
        let total = items.len() as i64;
        let raw_average: f64 = items
            .iter()
            .map(|f| normalise(f.value, f.decimals))
            .sum::<f64>()
            / total as f64;

        // Per cluster: the strongest single member's weight, and the score
        // that member gave, averaged across that cluster's opinions.
        let mut cluster_best: HashMap<i64, (f64, f64, f64)> = HashMap::new();
        for f in &items {
            let w = weights.get(&f.reviewer).copied().unwrap_or(1.0);
            let cid = clusters.get(&f.reviewer).copied().unwrap_or(-1);
            let s = normalise(f.value, f.decimals);
            let entry = cluster_best.entry(cid).or_insert((0.0, 0.0, 0.0));
            // Track the largest member weight, plus a weighted mean opinion.
            if w > entry.0 {
                entry.0 = w;
            }
            entry.1 += w * s;
            entry.2 += w;
        }

        let mut s_sum = 0.0;
        let mut w_sum = 0.0;
        for (_cid, (best_weight, weighted_score, weight_total)) in cluster_best {
            if weight_total <= 0.0 {
                continue;
            }
            let opinion = weighted_score / weight_total;
            // The cluster contributes one voice, at its best member's weight.
            s_sum += best_weight * opinion;
            w_sum += best_weight;
        }

        let trust = if w_sum >= MIN_EVIDENCE {
            Some(100.0 * ((s_sum + PRIOR_M * mu) / (w_sum + PRIOR_M)))
        } else {
            None
        };

        out.push(AgentTrust {
            agent_id,
            trust,
            confidence: w_sum / (w_sum + PRIOR_M),
            raw_average: raw_average * 100.0,
            feedback_total: total,
            feedback_kept: w_sum.round() as i64,
        });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fb(agent: &str, reviewer: u8, value: f64) -> Feedback {
        Feedback {
            agent_id: agent.into(),
            reviewer: vec![reviewer],
            value,
            decimals: 0,
        }
    }

    #[test]
    fn normalisation_matches_the_registry_range() {
        assert_eq!(normalise(100.0, 0), 1.0);
        assert_eq!(normalise(0.0, 0), 0.0);
        assert_eq!(normalise(50.0, 0), 0.5);
        // 600 with one decimal is 60, which is what the registry holds.
        assert_eq!(normalise(600.0, 1), 0.6);
        // Out of range values are clamped, never reinterpreted.
        assert_eq!(normalise(-40.0, 0), 0.0);
        assert_eq!(normalise(4000.0, 0), 1.0);
    }

    /// The whole point: a farm of ten addresses must not outrank one real
    /// reviewer just by turning up ten times.
    #[test]
    fn a_farm_cannot_outvote_a_single_independent_reviewer() {
        let mut feedback = vec![fb("honest", 1, 70.0)];
        let mut weights = HashMap::new();
        let mut clusters = HashMap::new();
        weights.insert(vec![1u8], 1.0);
        clusters.insert(vec![1u8], 1);

        // Ten farm addresses all shouting 100 at the same agent.
        for id in 10..20u8 {
            feedback.push(fb("farmed", id, 100.0));
            weights.insert(vec![id], 0.25);
            clusters.insert(vec![id], 99);
        }
        // And one honest reviewer who thinks it is mediocre.
        feedback.push(fb("farmed", 2, 40.0));
        weights.insert(vec![2u8], 1.0);
        clusters.insert(vec![2u8], 2);

        let out = compute(&feedback, &weights, &clusters);
        let farmed = out.iter().find(|a| a.agent_id == "farmed").unwrap();
        let honest = out.iter().find(|a| a.agent_id == "honest").unwrap();

        assert_eq!(
            farmed.feedback_total, 11,
            "we still show every review we saw"
        );
        assert!(
            farmed.feedback_kept <= 2,
            "but ten farm addresses count as about one voice, got {}",
            farmed.feedback_kept
        );
        // The farm's perfect scores must not lift it above an agent with a
        // genuine, lower rating.
        assert!(
            farmed.trust.unwrap() < honest.trust.unwrap(),
            "farmed {:?} should not beat honest {:?}",
            farmed.trust,
            honest.trust
        );
    }

    #[test]
    fn confidence_grows_with_independent_evidence() {
        let mut weights = HashMap::new();
        let mut clusters = HashMap::new();
        let thin = [fb("a", 1, 90.0)];
        weights.insert(vec![1u8], 1.0);
        clusters.insert(vec![1u8], 1);

        let mut thick = Vec::new();
        for id in 20..40u8 {
            thick.push(fb("b", id, 90.0));
            weights.insert(vec![id], 1.0);
            clusters.insert(vec![id], id as i64);
        }

        let all: Vec<Feedback> = thin.iter().chain(thick.iter()).cloned().collect();
        let out = compute(&all, &weights, &clusters);
        let a = out.iter().find(|x| x.agent_id == "a").unwrap();
        let b = out.iter().find(|x| x.agent_id == "b").unwrap();
        assert!(a.confidence < 0.2, "one review is thin evidence");
        assert!(b.confidence > 0.75, "twenty independent reviews is not");
    }

    /// An agent buried in farm reviews must show an absence, not a score.
    #[test]
    fn a_farmed_agent_gets_no_score_at_all() {
        let mut feedback = Vec::new();
        let mut weights = HashMap::new();
        let mut clusters = HashMap::new();
        // Two hundred reviews, every one from a heavily downweighted farm.
        for i in 0..200u32 {
            let id = (10 + (i % 20)) as u8;
            feedback.push(fb("farmed", id, 100.0));
            weights.insert(vec![id], 0.044);
            clusters.insert(vec![id], 99);
        }
        let out = compute(&feedback, &weights, &clusters);
        let a = &out[0];
        assert_eq!(a.feedback_total, 200, "we still report every review we saw");
        assert!(
            a.trust.is_none(),
            "no independent evidence means no score, got {:?}",
            a.trust
        );
        assert!(a.confidence < 0.05, "and the confidence says so too");
    }

    #[test]
    fn an_agent_with_no_surviving_weight_gets_no_score() {
        let feedback = vec![fb("x", 1, 100.0)];
        let mut weights = HashMap::new();
        let mut clusters = HashMap::new();
        weights.insert(vec![1u8], 0.0);
        clusters.insert(vec![1u8], 1);
        let out = compute(&feedback, &weights, &clusters);
        assert!(
            out[0].trust.is_none(),
            "no evidence means no number, not a middling one"
        );
        assert_eq!(out[0].feedback_total, 1, "and we still say we saw it");
    }

    #[test]
    fn raw_average_is_reported_untouched_for_the_side_by_side() {
        let feedback = vec![fb("x", 1, 100.0), fb("x", 2, 0.0)];
        let mut weights = HashMap::new();
        let mut clusters = HashMap::new();
        weights.insert(vec![1u8], 0.02);
        weights.insert(vec![2u8], 1.0);
        clusters.insert(vec![1u8], 1);
        clusters.insert(vec![2u8], 2);
        let out = compute(&feedback, &weights, &clusters);
        assert_eq!(
            out[0].raw_average, 50.0,
            "the registry's own average is untouched"
        );
    }
}
