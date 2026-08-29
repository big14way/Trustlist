import { CollapseCounter } from "@/components/CollapseCounter";
import { HireButton } from "@/components/HireButton";
import { ProbeStrip } from "@/components/ProbeStrip";
import { fetchAgents, fetchStats, fetchUptime } from "@/lib/api-server";
import type { AgentCard, UptimeMap } from "@/lib/api";

// Data comes from our indexer and prober at request time; never prerender
// stale counts.
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

function Card({ agent, uptime }: { agent: AgentCard; uptime: UptimeMap }) {
  const date = new Date(agent.registered_at).toISOString().slice(0, 10);
  const uptimePct = agent.uptime_7d
    ? `${(parseFloat(agent.uptime_7d) * 100).toFixed(1)}%`
    : "n/a";
  return (
    <li className="rounded-lg border border-dormant/40 bg-paper p-4 transition-colors hover:border-ink/40">
      <div className="flex items-start justify-between gap-2">
        <h2 className="font-display text-lg leading-tight">
          <a
            href={`/agents/${agent.agent_id}`}
            className="hover:underline focus-visible:underline"
          >
            {agent.name ?? `Agent #${agent.agent_id}`}
          </a>
        </h2>
        <StatusPill status={agent.status} />
      </div>
      <p className="mt-1 line-clamp-2 min-h-10 text-sm text-ink/80">
        {agent.description ?? "No description in the agent card."}
      </p>
      <div className="mt-3">
        <ProbeStrip
          buckets={uptime[agent.agent_id] ?? []}
          label={agent.name ?? `Agent ${agent.agent_id}`}
        />
      </div>
      <div className="mt-2 flex items-center justify-between gap-2">
        <p className="font-data text-xs text-ink/70">
          UPTIME {uptimePct} · PROBES {agent.probes_7d ?? 0} · REVIEWS{" "}
          {agent.feedback_total} · {date}
        </p>
        <HireButton
          agentId={agent.agent_id}
          agentName={agent.name ?? `Agent ${agent.agent_id}`}
          provider={agent.owner}
          variant="compact"
        />
      </div>
    </li>
  );
}

const CATEGORIES = [
  { id: "", label: "All" },
  { id: "monitoring", label: "Monitoring" },
  { id: "grid-trading", label: "Grid trading" },
  { id: "yield", label: "Yield" },
  { id: "health-factor", label: "Health factor" },
  { id: "rebalancing", label: "Rebalancing" },
  { id: "pancakeswap", label: "PancakeSwap" },
];

function FilterRail({
  category,
  showDormant,
  dormantCount,
}: {
  category: string;
  showDormant: boolean;
  dormantCount: number;
}) {
  const href = (c: string, d: boolean) => {
    const p = new URLSearchParams();
    if (c) p.set("category", c);
    if (d) p.set("dormant", "1");
    const qs = p.toString();
    return qs ? `/?${qs}` : "/";
  };
  return (
    <div className="mt-6">
      <ul className="flex flex-wrap gap-2">
        {CATEGORIES.map((c) => (
          <li key={c.id}>
            <a
              href={href(c.id, showDormant)}
              className={`inline-block rounded border px-3 py-1 text-sm ${
                category === c.id
                  ? "border-ink bg-ink text-paper"
                  : "border-dormant/50 hover:border-ink"
              }`}
            >
              {c.label}
            </a>
          </li>
        ))}
      </ul>
      <p className="mt-3 text-xs">
        <a
          href={href(category, !showDormant)}
          className="underline text-ink/70 hover:text-ink"
        >
          {showDormant
            ? "Hide the agents that never answer"
            : `Show the ${dormantCount.toLocaleString()} agents that never answer`}
        </a>
      </p>
    </div>
  );
}

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ category?: string; dormant?: string }>;
}) {
  const sp = await searchParams;
  const category = sp.category ?? "";
  const showDormant = sp.dormant === "1";

  const stats = await fetchStats();
  // Default marketplace filter: only agents whose status is earned by
  // enough probes appear. The measuring majority is a count, not a listing.
  const query = new URLSearchParams({
    sort: "rank",
    limit: "24",
    status: showDormant ? "down,dormant" : "live,flaky",
  });
  if (category) query.set("category", category);
  const agents = await fetchAgents(query);
  const uptime =
    (await fetchUptime(agents?.items.map((a) => a.agent_id) ?? [])) ?? {};

  const measured = stats?.measured === true;
  const answering = measured && stats ? stats.live + stats.flaky : 0;

  return (
    <main className="mx-auto max-w-[1200px] px-8 py-16">
      <p className="eyebrow text-dormant">ERC-8004 / BNB SMART CHAIN</p>
      <h1 className="font-display mt-3 text-5xl text-ink">
        Most agents are not there.
      </h1>

      {stats && measured ? (
        answering > 0 ? (
          <p className="mt-4 max-w-2xl text-base">
            <CollapseCounter
              registered={stats.registered}
              answering={answering}
            />{" "}
            of{" "}
            <span className="font-data">
              {stats.registered.toLocaleString()}
            </span>{" "}
            registered agents answer when probed. We check every 30 minutes and
            keep the history.
          </p>
        ) : (
          <p className="mt-4 max-w-2xl text-base">
            <span className="font-data">
              {stats.registered.toLocaleString()}
            </span>{" "}
            agents registered.{" "}
            <span className="font-data">
              {stats.with_endpoints.toLocaleString()}
            </span>{" "}
            declare an endpoint, and we are probing every one of them every 30
            minutes ({stats.probes_total.toLocaleString()} probes recorded so
            far). Statuses appear once an agent has enough probes to judge
            fairly; until then nothing here claims to be alive.
          </p>
        )
      ) : stats ? (
        <p className="mt-4 max-w-2xl text-base">
          The prober has not completed its first scoring pass, so we have
          nothing measured to report yet. We would rather say that than show you
          a zero and call it a finding.
        </p>
      ) : (
        <p className="mt-4 max-w-2xl text-base text-flag">
          The API is not reachable. Counts and agents cannot be shown, and we
          will not show cached or invented numbers in their place.
        </p>
      )}

      {stats && measured && stats.indexed_to_block ? (
        <p className="font-data mt-2 text-xs text-dormant">
          indexed to block {stats.indexed_to_block.toLocaleString()} · live{" "}
          {stats.live} · flaky {stats.flaky} · down {stats.down} · measuring{" "}
          {stats.measuring}
          {stats.computed_at
            ? ` · scored ${stats.computed_at.slice(0, 16).replace("T", " ")}Z`
            : ""}
        </p>
      ) : null}

      <FilterRail
        category={category}
        showDormant={showDormant}
        dormantCount={stats ? stats.down + stats.measuring : 0}
      />

      <section aria-label="Agents" className="mt-8">
        <p className="eyebrow text-dormant">
          {showDormant
            ? "AGENTS THAT DO NOT ANSWER, OR HAVE NOT BEEN MEASURED ENOUGH YET"
            : "AGENTS THAT ANSWER, RANKED"}
          {category ? ` · ${category.toUpperCase()}` : ""}
        </p>
        {agents && agents.items.length > 0 ? (
          <ul className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {agents.items.map((a) => (
              <Card key={a.agent_id} agent={a} uptime={uptime} />
            ))}
          </ul>
        ) : (
          <p className="mt-4 max-w-xl text-sm text-ink/70">
            {category
              ? `No agent in this category is answering right now. Try another category, or show the agents that never answer to see who claimed the label without backing it up.`
              : "Nothing to show yet. The prober is measuring; reload in a minute."}
          </p>
        )}
      </section>

      <footer className="mt-16 border-t border-dormant/40 pt-6">
        <nav className="font-data mb-3 flex flex-wrap gap-4 text-xs">
          <a className="underline" href="/jobs">
            My hires
          </a>
          <a className="underline" href="/stats">
            Registry health
          </a>
          <a className="underline" href="/sessions">
            Spend caps
          </a>
          <a className="underline" href="/methodology">
            How the numbers are made
          </a>
          <a
            className="underline"
            href="https://github.com/big14way/Trustlist"
            target="_blank"
            rel="noreferrer"
          >
            Source
          </a>
        </nav>
        <p className="font-data text-xs text-dormant">
          M2: probing and liveness. Trust scoring and hiring arrive in the
          milestones behind this page. Every number and every probe cell above
          is a database read from our own instruments.
        </p>
      </footer>
    </main>
  );
}
