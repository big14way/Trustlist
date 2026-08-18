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
