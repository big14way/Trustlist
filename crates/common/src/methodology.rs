//! Every tunable number the trust engine uses, in one place.
//!
//! The API serves this struct at /v1/methodology and the public methodology
//! page renders from that response, so what a reader is told and what the
//! engine actually does cannot drift apart. Changing a threshold here
//! changes the published rules in the same commit.

use serde::Serialize;

/// A penalty applied to a reviewer's weight, with the reason a human would
/// give for it.
#[derive(Debug, Clone, Serialize)]
pub struct Penalty {
    pub id: &'static str,
    pub factor: f64,
    pub detects: &'static str,
    pub why: &'static str,
}

#[derive(Debug, Clone, Serialize)]
pub struct Methodology {
    pub liveness: Liveness,
    pub reputation: Reputation,
    pub ranking: Ranking,
    pub known_weaknesses: Vec<&'static str>,
}

#[derive(Debug, Clone, Serialize)]
pub struct Liveness {
    pub formula: &'static str,
    pub uptime_weight: f64,
    pub card_quality_weight: f64,
    pub latency_weight: f64,
    pub latency_ceiling_ms: u32,
    pub probe_interval_secs: u32,
    pub bulk_host_probe_interval_secs: u32,
    pub min_probes_for_a_status: u32,
    pub min_probes_daily_cadence: u32,
    pub live_threshold: f64,
    pub flaky_threshold: f64,
    pub alive_http_statuses: &'static str,
    pub dead_http_statuses: &'static str,
    pub observer_outage_rule: &'static str,
}

#[derive(Debug, Clone, Serialize)]
pub struct Reputation {
    pub scale: &'static str,
    pub prior_strength: f64,
    pub min_evidence_to_publish: f64,
    pub weight_floor: f64,
    pub funding_cluster_size: usize,
    pub coreview_shared_agents: i64,
    pub coreview_peers: i64,
    pub fresh_window_secs: i64,
    pub cluster_cap_rule: &'static str,
    pub penalties: Vec<Penalty>,
}

#[derive(Debug, Clone, Serialize)]
pub struct Ranking {
    pub formula: &'static str,
    pub liveness_weight: f64,
    pub trust_weight: f64,
    pub default_filter: &'static str,
}

/// The published parameter set. Values here are the ones the engine uses.
pub fn current() -> Methodology {
    Methodology {
        liveness: Liveness {
            formula: "liveness = 100 * (0.55*uptime_7d + 0.30*card_quality + 0.15*latency_factor)",
            uptime_weight: 0.55,
            card_quality_weight: 0.30,
            latency_weight: 0.15,
            latency_ceiling_ms: 5000,
            probe_interval_secs: 1800,
            bulk_host_probe_interval_secs: 86400,
            min_probes_for_a_status: 24,
            min_probes_daily_cadence: 6,
            live_threshold: 0.9,
            flaky_threshold: 0.5,
            alive_http_statuses:
                "any status below 500 except 404. A 401, 402, or 403 means the endpoint answered and wants payment or a key, which is a working agent.",
            dead_http_statuses:
                "404, any 5xx, and every transport failure: dns, tls, connection refused, timeout.",
            observer_outage_rule:
                "an hour in which we sent more than 100 probes and fewer than 5 percent succeeded is treated as our outage, not theirs. Those hours are excluded from uptime and shown as no data. The probes are never deleted.",
        },
        reputation: Reputation {
            scale:
                "The registry stores a signed int128 with a per event decimals field and defines no scale. We divide by 10^decimals, clamp into 0..100, and read that as a percentage. Every feedback event on BSC today lands inside that range once scaled, so the clamp is a guard rather than a reinterpretation.",
            prior_strength: crate::methodology::PRIOR_M,
            min_evidence_to_publish: crate::methodology::MIN_EVIDENCE,
            weight_floor: crate::methodology::WEIGHT_FLOOR,
            funding_cluster_size: crate::methodology::CLUSTER_LARGE,
            coreview_shared_agents: crate::methodology::MIN_SHARED_AGENTS,
            coreview_peers: crate::methodology::COREVIEW_PEERS,
            fresh_window_secs: crate::methodology::FRESH_WINDOW_SECS,
            cluster_cap_rule:
                "For each agent, reviewers are grouped by cluster and a cluster contributes one voice at the weight of its strongest member. Without this, twenty downweighted addresses still outvote one real reviewer by sheer count.",
            penalties: penalties(),
        },
        ranking: Ranking {
            formula: "rank_score = 0.45*liveness + 0.35*trust",
            liveness_weight: 0.45,
            trust_weight: 0.35,
            default_filter:
                "Only agents that earned a status by being probed enough appear by default. The measuring majority is reported as a count, not listed as if it were ranked.",
        },
        known_weaknesses: vec![
            "Funding traces follow only the first inbound transfer. An operator who funds each reviewer from a fresh intermediate wallet would not form a cluster under this rule.",
            "The co-review signal needs a reviewer to overlap with several others. Two addresses working as a pair can stay below it.",
            "We cannot enumerate a reviewer's full transaction history cheaply, so 'barely transacts outside the registry' uses transfer counts rather than every contract call.",
            "A high trust score still means only that independent looking addresses said good things. It is not a guarantee about future work.",
            "Uptime is measured from one vantage point. An endpoint that is reachable from elsewhere but not from us reads as down, which is why the observer outage rule exists and why we publish the probe history rather than only the summary.",
            "Agents that are new or rarely probed are excluded from the default ranking rather than scored badly, so a good new agent is invisible until it has been measured. That is deliberate and it is a cost.",
        ],
    }
}

// Values shared with the trust engine. Changing one changes both the
// computation and the published rules.
pub const WEIGHT_FLOOR: f64 = 0.02;
pub const CLUSTER_LARGE: usize = 5;
pub const MIN_SHARED_AGENTS: i64 = 20;
pub const COREVIEW_PEERS: i64 = 3;
pub const PRIOR_M: f64 = 5.0;
pub const MIN_EVIDENCE: f64 = 1.0;

/// How soon after being funded a first review counts as "provisioned to
/// vote". The spec's first guess was seven days; the registry's own data
/// draws the line far tighter. Grouping every reviewer by the gap between
/// its funding and its first review gives: under a minute, 28 addresses
/// averaging 0.3 other transfers; under an hour, 12 averaging 0.9; under a
/// day, 7 averaging 2.3; under a week, 5 averaging 28.2; longer, 51
/// averaging 63.0. Everything inside a day has essentially no other life on
/// chain, and everything past a week clearly does. So the threshold is a
/// day, and a genuinely new person who funds a wallet and reviews later in
/// the week is not punished for it.
pub const FRESH_WINDOW_SECS: i64 = 86_400;

pub const P_FUNDING_CLUSTER: f64 = 0.25;
pub const P_SHARED_FUNDER: f64 = 0.5;
pub const P_COREVIEW_RING: f64 = 0.35;
pub const P_ONE_SHOT: f64 = 0.3;
pub const P_NO_OTHER_ACTIVITY: f64 = 0.5;
pub const P_SINGLE_VALUE_ONLY: f64 = 0.5;
pub const P_FRESH_ADDRESS: f64 = 0.5;
pub const P_RECIPROCAL: f64 = 0.4;
pub const P_HIGH_REVOCATION: f64 = 0.3;

pub fn penalties() -> Vec<Penalty> {
    vec![
        Penalty {
            id: "funding_cluster",
            factor: P_FUNDING_CLUSTER,
            detects: "five or more reviewers whose first transaction was paid for by the same wallet",
            why: "Somebody who pays the gas for a crowd of reviewers is running them, not meeting them. This is the signal that catches the farm operating on BSC today.",
        },
        Penalty {
            id: "shared_funder",
            factor: P_SHARED_FUNDER,
            detects: "two to four reviewers sharing a funder",
            why: "A pair can be colleagues or one person with two wallets. Suspicious, not damning.",
        },
        Penalty {
            id: "coreview_ring",
            factor: P_COREVIEW_RING,
            detects: "reviews at least 20 of the same agents as 3 or more other reviewers",
            why: "The farm on BSC is patient: it drips reviews out over weeks rather than firing them in a burst, so a timing detector misses it entirely. What it cannot hide is that the same addresses keep showing up on the same agents.",
        },
        Penalty {
            id: "one_shot",
            factor: P_ONE_SHOT,
            detects: "exactly one review, and fewer than five transfers ever",
            why: "An address created to say one thing and then never used again is not a participant.",
        },
        Penalty {
            id: "no_other_activity",
            factor: P_NO_OTHER_ACTIVITY,
            detects: "fewer than five transfers out, ever",
            why: "Reputation should cost something. An address with no other life on chain paid nothing to have an opinion.",
        },
        Penalty {
            id: "single_value_only",
            factor: P_SINGLE_VALUE_ONLY,
            detects: "three or more reviews that are all the identical score",
            why: "A reviewer who has never once distinguished between two agents is not evaluating them.",
        },
        Penalty {
            id: "fresh_address",
            factor: P_FRESH_ADDRESS,
            detects: "funded less than 24 hours before its first review",
            why: "Wallets created just in time to vote are the oldest trick there is. We measured where the line actually falls on this registry: addresses that reviewed within a day of being funded average under three other transfers ever, while those funded a week or more beforehand average sixty three. A day is where provisioning stops and real use starts.",
        },
        Penalty {
            id: "reciprocal",
            factor: P_RECIPROCAL,
            detects: "rates an agent whose owner rates an agent it owns",
            why: "Mutual praise between two owners is an arrangement, not evidence.",
        },
        Penalty {
            id: "high_revocation",
            factor: P_HIGH_REVOCATION,
            detects: "three or more reviews, at least half later revoked",
            why: "Feedback written and withdrawn is a way to be counted in a snapshot and then vanish.",
        },
    ]
}
