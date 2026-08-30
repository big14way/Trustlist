import { cache } from "react";
import {
  apiGet,
  apiGetResult,
  type Fetched,
  type AgentCard,
  type AgentList,
  type EndpointState,
  type Reviews,
  type Methodology,
  type Stats,
  type UptimeBuckets,
  type UptimeMap,
} from "./api";

// Next renders a dynamic page twice for a single request: once for the HTML
// and once for the payload the browser hydrates against. Our numbers change
// every second as probes land, so without a per request snapshot those two
// passes disagree and React discards the page and rebuilds it in the
// browser. React's cache gives both passes the same answer.
const snapshot = cache(async (path: string): Promise<unknown> => apiGet(path));

async function get<T>(path: string): Promise<T | null> {
  return (await snapshot(path)) as T | null;
}

export function fetchStats(): Promise<Stats | null> {
  return get<Stats>("/v1/stats");
}

export function fetchAgents(
  params: URLSearchParams,
): Promise<AgentList | null> {
  const qs = params.toString();
  return get<AgentList>(`/v1/agents${qs ? `?${qs}` : ""}`);
}

export function fetchUptime(ids: string[]): Promise<UptimeMap | null> {
  if (ids.length === 0) return Promise.resolve({});
  return get<UptimeMap>(`/v1/uptime?ids=${ids.join(",")}`);
}

export function fetchAgent(id: string): Promise<AgentCard | null> {
  return get<AgentCard>(`/v1/agents/${encodeURIComponent(id)}`);
}

// The agent page is the one place where the difference between a missing
// agent and an unreachable API changes what the reader is told, so it does
// not share the snapshot cache above.
export function fetchAgentResult(id: string): Promise<Fetched<AgentCard>> {
  return apiGetResult<AgentCard>(`/v1/agents/${encodeURIComponent(id)}`);
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

export function fetchMethodology(): Promise<Methodology | null> {
  return get<Methodology>("/v1/methodology");
}
