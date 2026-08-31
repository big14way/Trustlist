// Typed API client. The web app talks only to our API, never to an agent
// endpoint directly.
//
// This module is safe to import from client components. Server components
// should use lib/api-server.ts instead, which snapshots each request.

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";

export type AgentCard = {
  agent_id: string;
  name: string | null;
  description: string | null;
  categories: string[];
  status: "live" | "flaky" | "down" | "dormant" | "measuring";
  card_status: string | null;
  endpoints: { kind: string; url: string }[] | null;
  owner: string;
  registered_at: string;
  registered_block: number;
  token_uri_scheme: string | null;
  liveness: string | null;
  uptime_7d: string | null;
  median_latency_ms: number | null;
  probes_7d: number | null;
  trust: string | null;
  trust_confidence: string | null;
  feedback_total: number;
  feedback_kept: number | null;
  jobs_completed: number;
  jobs_disputed: number;
};

export type AgentList = {
  items: AgentCard[];
  next_cursor: string | null;
  total_unfiltered: number;
};

export type Stats = {
  /// Answering agents per category. Absent before the first scoring pass.
  categories?: Record<string, number>;
  /// False before the first scoring pass, when we genuinely have nothing
  /// measured yet and the page must say so rather than print zeroes.
  measured: boolean;
  computed_at?: string;
  registered: number;
  cards_ok: number;
  with_endpoints: number;
  cards_fetched: number;
  feedback: number;
  reviewers: number;
  live: number;
  flaky: number;
  down: number;
  measuring: number;
  probes_total: number;
  agents_rated: number;
  agents_scored: number;
  reviews_kept: number;
  reviewers_independent: number;
  largest_cluster_reviewers: number;
  largest_cluster_reviews: number;
  indexed_to_block: number | null;
  indexed_at: string | null;
};

export type UptimeMap = Record<
  string,
  { hour: string; ok_share: number | null; probes: number }[]
>;

// Every external call gets a timeout. Without one, an API that accepts the
// connection and then stalls holds the page render open until the platform
// gives up, which reads to a visitor as a site that hangs rather than a site
// whose API is down. Eight seconds is well past our slowest measured
// endpoint and well inside anyone's patience.
const TIMEOUT_MS = 8000;

export async function apiGet<T>(path: string): Promise<T | null> {
  const r = await apiGetResult<T>(path);
  return r.ok ? r.data : null;
}

/// "We could not find it" and "we could not ask" are different answers, and
/// a page that collapses them tells the reader the wrong thing: a missing
/// agent page shown during an outage claims an agent does not exist when it
/// does. Callers that show one of those states use this instead of apiGet.
export type Fetched<T> =
  | { ok: true; data: T }
  | { ok: false; reason: "missing" | "unreachable" };

export async function apiGetResult<T>(path: string): Promise<Fetched<T>> {
  try {
    const res = await fetch(`${API_URL}${path}`, {
      cache: "no-store",
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (res.status === 404) return { ok: false, reason: "missing" };
    if (!res.ok) {
      console.error(`API returned ${res.status} for ${path}`);
      return { ok: false, reason: "unreachable" };
    }
    return { ok: true, data: (await res.json()) as T };
  } catch (e) {
    console.error(`API fetch failed for ${path}`, e);
    return { ok: false, reason: "unreachable" };
  }
}

export function fetchStats(): Promise<Stats | null> {
  return apiGet<Stats>("/v1/stats");
}

export function fetchAgents(
  params: URLSearchParams,
): Promise<AgentList | null> {
  const qs = params.toString();
  return apiGet<AgentList>(`/v1/agents${qs ? `?${qs}` : ""}`);
}

export function fetchUptime(ids: string[]): Promise<UptimeMap | null> {
  if (ids.length === 0) return Promise.resolve({});
  return apiGet<UptimeMap>(`/v1/uptime?ids=${ids.join(",")}`);
}

export type EndpointState = {
  url: string;
  kind: string;
  cadence_secs: number;
  last_probed_at: string | null;
  last_ok: boolean | null;
  last_http_status: number | null;
  last_latency_ms: number | null;
  last_failure_kind: string | null;
  probes_7d: number;
  ok_7d: number;
};

export type Review = {
  reviewer: string;
  value: string;
  value_decimals: number;
  tags: string[];
  uri: string | null;
  revoked: boolean;
  block_time: string;
  tx_hash: string;
  /// 0..1. How much this reviewer's opinion counts, and why.
  weight: string | null;
  flags: string[];
  cluster_id: string | null;
  /// The wallet that paid for this reviewer's first transaction.
  funder: string | null;
};

export type Reviews = {
  agent_id: string;
  total: number;
  revoked: number;
  distinct_reviewers: number;
  /// Independent voices left after weighting, which can be zero even when
  /// hundreds of reviews exist.
  kept: number | null;
  trust: string | null;
  raw_average: string | null;
  confidence: string | null;
  items: Review[];
};

export type UptimeBuckets = {
  agent_id: string;
  buckets: { hour: string; ok_share: number | null; probes: number }[];
};

export function fetchAgent(id: string): Promise<AgentCard | null> {
  return apiGet<AgentCard>(`/v1/agents/${encodeURIComponent(id)}`);
}

export function fetchAgentUptime(id: string): Promise<UptimeBuckets | null> {
  return apiGet<UptimeBuckets>(`/v1/agents/${encodeURIComponent(id)}/uptime`);
}

export function fetchAgentReviews(id: string): Promise<Reviews | null> {
  return apiGet<Reviews>(`/v1/agents/${encodeURIComponent(id)}/reviews`);
}

export function fetchAgentEndpoints(
  id: string,
): Promise<{ agent_id: string; items: EndpointState[] } | null> {
  return apiGet<{ agent_id: string; items: EndpointState[] }>(
    `/v1/agents/${encodeURIComponent(id)}/endpoints`,
  );
}

export type Job = {
  job_id: string;
  agent_id: string;
  agent_name: string | null;
  hirer: string;
  provider: string | null;
  budget: string;
  refunded: string | null;
  state: string;
  mode: string;
  kernel_status: number | null;
  chain_id: number;
  spec: string | null;
  created_at: string;
  deadline: string | null;
  submitted_at: string | null;
  settled_at: string | null;
  create_tx: string | null;
  settle_tx: string | null;
};

export function fetchJobs(hirer?: string): Promise<{ items: Job[] } | null> {
  const qs = hirer ? `?hirer=${encodeURIComponent(hirer)}` : "";
  return apiGet<{ items: Job[] }>(`/v1/jobs${qs}`);
}

export type Penalty = {
  id: string;
  factor: number;
  detects: string;
  why: string;
};

export type CategoryRule = {
  id: string;
  matches: string;
  matched_agents_note: string;
};

export type Methodology = {
  categories: {
    how: string;
    caveat: string;
    rules: CategoryRule[];
  };
  liveness: {
    formula: string;
    uptime_weight: number;
    card_quality_weight: number;
    latency_weight: number;
    latency_ceiling_ms: number;
    probe_interval_secs: number;
    bulk_host_probe_interval_secs: number;
    min_probes_for_a_status: number;
    min_probes_daily_cadence: number;
    live_threshold: number;
    flaky_threshold: number;
    alive_http_statuses: string;
    dead_http_statuses: string;
    observer_outage_rule: string;
  };
  reputation: {
    scale: string;
    prior_strength: number;
    min_evidence_to_publish: number;
    weight_floor: number;
    funding_cluster_size: number;
    coreview_shared_agents: number;
    coreview_peers: number;
    fresh_window_secs: number;
    cluster_cap_rule: string;
    penalties: Penalty[];
  };
  ranking: {
    formula: string;
    liveness_weight: number;
    trust_weight: number;
    default_filter: string;
  };
  publication: {
    what: string;
    leaf_encoding: string;
    build_interval_secs: number;
    who_can_publish: string;
    caveat: string;
    how_to_check: string;
  };
  known_weaknesses: string[];
};
