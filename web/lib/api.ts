// Typed API client. The web app talks only to our API, never to an agent
// endpoint directly.

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
  trust: number | null;
  trust_confidence: number | null;
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
  indexed_to_block: number | null;
  indexed_at: string | null;
};

export type UptimeMap = Record<
  string,
  { hour: string; ok_share: number | null; probes: number }[]
>;

async function get<T>(path: string): Promise<T | null> {
  try {
    const res = await fetch(`${API_URL}${path}`, {
      next: { revalidate: 30 },
    });
    if (!res.ok) return null;
    return (await res.json()) as T;
  } catch (e) {
    console.error(`API fetch failed for ${path}`, e);
    return null;
  }
}

export function fetchStats(): Promise<Stats | null> {
  return get<Stats>("/v1/stats");
}

export function fetchAgents(params: URLSearchParams): Promise<AgentList | null> {
  const qs = params.toString();
  return get<AgentList>(`/v1/agents${qs ? `?${qs}` : ""}`);
}

export function fetchUptime(ids: string[]): Promise<UptimeMap | null> {
  if (ids.length === 0) return Promise.resolve({});
  return get<UptimeMap>(`/v1/uptime?ids=${ids.join(",")}`);
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
  weight: number | null;
  flags: string[];
};

export type Reviews = {
  agent_id: string;
  total: number;
  revoked: number;
  distinct_reviewers: number;
  kept: number | null;
  items: Review[];
};

export type UptimeBuckets = {
  agent_id: string;
  buckets: { hour: string; ok_share: number | null; probes: number }[];
};

export function fetchAgent(id: string): Promise<AgentCard | null> {
  return get<AgentCard>(`/v1/agents/${encodeURIComponent(id)}`);
}

export function fetchAgentUptime(id: string): Promise<UptimeBuckets | null> {
  return get<UptimeBuckets>(`/v1/agents/${encodeURIComponent(id)}/uptime`);
}

export function fetchAgentReviews(id: string): Promise<Reviews | null> {
  return get<Reviews>(`/v1/agents/${encodeURIComponent(id)}/reviews`);
}

export function fetchAgentEndpoints(
  id: string,
): Promise<{ agent_id: string; items: EndpointState[] } | null> {
  return get<{ agent_id: string; items: EndpointState[] }>(
    `/v1/agents/${encodeURIComponent(id)}/endpoints`,
  );
}
