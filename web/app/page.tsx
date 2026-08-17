import { fetchAgents, fetchStats, type AgentCard } from "@/lib/api";

// Data comes from our indexer at request time; never prerender stale counts.
export const dynamic = "force-dynamic";

function StatusPill({ status }: { status: AgentCard["status"] }) {
  const styles: Record<AgentCard["status"], string> = {
    live: "bg-signal text-ink",
    flaky: "bg-signal/50 text-ink",
    down: "bg-dormant/40 text-ink",
    dormant: "bg-dormant/40 text-ink/70",
    measuring: "border border-dormant text-ink/70",
  };
  return (
    <span
      className={`eyebrow inline-block rounded px-1.5 py-0.5 ${styles[status]}`}
    >
      {status}
    </span>
  );
}

function Card({ agent }: { agent: AgentCard }) {
  const date = new Date(agent.registered_at).toISOString().slice(0, 10);
  return (
    <li className="rounded-lg border border-dormant/40 bg-paper p-4">
      <div className="flex items-start justify-between gap-2">
        <h2 className="font-display text-lg leading-tight">
          {agent.name ?? `Agent #${agent.agent_id}`}
        </h2>
        <StatusPill status={agent.status} />
      </div>
      <p className="mt-1 line-clamp-2 min-h-10 text-sm text-ink/80">
        {agent.description ?? "No description in the agent card."}
      </p>
      <p className="font-data mt-3 text-xs text-ink/70">
        ID {agent.agent_id} · {date} ·{" "}
        {agent.endpoints?.length
          ? `${agent.endpoints.length} endpoint${agent.endpoints.length > 1 ? "s" : ""}`
          : "no endpoints"}{" "}
        · {agent.feedback_total} reviews
      </p>
    </li>
  );
}

export default async function Home() {
  const [stats, agents] = await Promise.all([
    fetchStats(),
    fetchAgents(new URLSearchParams({ status: "measuring", limit: "24" })),
  ]);

  return (
    <main className="mx-auto max-w-[1200px] px-8 py-16">
      <p className="eyebrow text-dormant">ERC-8004 / BNB SMART CHAIN</p>
      <h1 className="font-display mt-3 text-5xl text-ink">
        Most agents are not there.
      </h1>

      {stats ? (
        <p className="mt-4 max-w-2xl text-base">
          <span className="font-data">{stats.registered.toLocaleString()}</span>{" "}
          agents indexed from the ERC-8004 registry so far,{" "}
          <span className="font-data">
            {stats.with_endpoints.toLocaleString()}
          </span>{" "}
          declare a service endpoint. Probing begins in the next milestone;
          until we have probed, nothing here claims to be alive.
        </p>
      ) : (
        <p className="mt-4 max-w-2xl text-base text-flag">
          The API is not reachable. Counts and agents cannot be shown, and we
          will not show cached or invented numbers in their place.
        </p>
      )}

      {stats?.indexed_to_block ? (
        <p className="font-data mt-2 text-xs text-dormant">
          indexed to block {stats.indexed_to_block.toLocaleString()}
          {stats.indexed_at ? ` at ${stats.indexed_at.slice(0, 19)}Z` : ""}
          {" · backfill in progress, the count grows until it reaches head"}
        </p>
      ) : null}

      <section aria-label="Agents" className="mt-12">
        <p className="eyebrow text-dormant">
          AGENTS WITH A DECLARED ENDPOINT, NEWEST FIRST
        </p>
        {agents && agents.items.length > 0 ? (
          <ul className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {agents.items.map((a) => (
              <Card key={a.agent_id} agent={a} />
            ))}
          </ul>
        ) : (
          <p className="mt-4 text-sm text-ink/70">
            No agents with endpoints indexed yet. The backfill is running;
            reload in a minute.
          </p>
        )}
      </section>

      <footer className="mt-16 border-t border-dormant/40 pt-6">
        <p className="font-data text-xs text-dormant">
          M1: index and see. Probing, trust scoring, and hiring arrive in the
          milestones behind this page. Every number above is a database read
          from our own chain indexer.
        </p>
      </footer>
    </main>
  );
}
