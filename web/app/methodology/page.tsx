import { fetchMethodology, fetchStats } from "@/lib/api-server";

// Rendered from /v1/methodology, which serves the same constants the trust
// engine runs on. If a threshold changes, this page changes with it in the
// same commit, because there is only one copy of each number.
export const dynamic = "force-dynamic";

function Row({ k, v }: { k: string; v: string }) {
  return (
    <div className="flex flex-wrap justify-between gap-4 border-t border-dormant/30 py-2">
      <span className="text-sm">{k}</span>
      <span className="font-data text-sm">{v}</span>
    </div>
  );
}

export default async function MethodologyPage() {
  const [m, stats] = await Promise.all([fetchMethodology(), fetchStats()]);

  if (!m) {
    return (
      <main className="mx-auto max-w-[820px] px-8 py-16">
        <p className="text-sm text-flag">
          The API is not reachable, so we cannot show you the rules we are
          running. We will not print a remembered copy in their place.
        </p>
      </main>
    );
  }

  const measured = stats?.measured === true;

  return (
    <main className="mx-auto max-w-[820px] px-8 py-16">
      <a href="/" className="eyebrow text-dormant hover:text-ink">
        &larr; ALL AGENTS
      </a>
      <h1 className="font-display mt-3 text-4xl">How the numbers are made</h1>
      <p className="mt-4 text-base">
        Everything on this site is computed from public chain data by the rules
        below. This page is generated from the same values the engine runs on,
        so it cannot drift from what actually happened. Where we are unsure, we
        say so, and the last section is a list of the ways this can be wrong.
      </p>

      {measured && stats ? (
        <p className="font-data mt-4 rounded border border-dormant/40 p-3 text-xs">
          Right now: {stats.registered.toLocaleString()} agents registered,{" "}
          {(stats.live + stats.flaky).toLocaleString()} answering when probed,{" "}
          {stats.probes_total.toLocaleString()} probes recorded,{" "}
          {stats.feedback.toLocaleString()} reviews on chain from{" "}
          {stats.reviewers} distinct addresses.
        </p>
      ) : null}

      <h2 className="font-display mt-10 text-2xl">What kind of agent is it</h2>
      <p className="mt-2 text-sm text-ink/80">{m.categories.how}</p>
      <ul className="mt-3">
        {m.categories.rules.map((c) => (
          <li key={c.id} className="border-t border-dormant/30 py-2">
            <span className="font-data text-sm">{c.id}</span>
            <p className="mt-1 text-sm text-ink/80">{c.matched_agents_note}</p>
            <p className="font-data mt-0.5 text-[11px] text-dormant">
              matches: {c.matches}
            </p>
          </li>
        ))}
      </ul>
      <p className="mt-3 text-sm text-ink/80">{m.categories.caveat}</p>

      <h2 className="font-display mt-10 text-2xl">Is the agent alive</h2>
      <p className="mt-2 text-sm text-ink/80">
        We resolve every agent&apos;s declared endpoints and call them on a
        schedule, keeping the whole history. Uptime is measured, not claimed.
      </p>
      <p className="font-data mt-3 text-xs">{m.liveness.formula}</p>
      <div className="mt-4">
        <Row
          k="Probe interval"
          v={`${m.liveness.probe_interval_secs / 60} minutes`}
        />
        <Row
          k="Interval for hosts serving many registrations"
          v={`${m.liveness.bulk_host_probe_interval_secs / 3600} hours`}
        />
        <Row
          k="Probes before we assign a status"
          v={`${m.liveness.min_probes_for_a_status}`}
        />
        <Row k="Live" v={`uptime at or above ${m.liveness.live_threshold}`} />
        <Row
          k="Flaky"
          v={`uptime ${m.liveness.flaky_threshold} to ${m.liveness.live_threshold}`}
        />
      </div>
      <p className="mt-3 text-sm text-ink/80">
        <strong>Counts as alive:</strong> {m.liveness.alive_http_statuses}
      </p>
      <p className="mt-2 text-sm text-ink/80">
        <strong>Counts as down:</strong> {m.liveness.dead_http_statuses}
      </p>
      <p className="mt-2 text-sm text-ink/80">
        <strong>When the fault is ours:</strong>{" "}
        {m.liveness.observer_outage_rule}
      </p>

      <h2 className="font-display mt-10 text-2xl">Is the praise real</h2>
      <p className="mt-2 text-sm text-ink/80">{m.reputation.scale}</p>
      <p className="mt-3 text-sm text-ink/80">
        Every address that has left feedback starts at full weight and is
        multiplied down by each signal that it is not an independent voice. We
        downweight rather than delete, and the floor is{" "}
        {m.reputation.weight_floor}, never zero, so we can always tell you how
        many reviews we saw next to how many we counted.
      </p>
      <ul className="mt-4">
        {m.reputation.penalties.map((p) => (
          <li key={p.id} className="border-t border-dormant/30 py-3">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <span className="font-data text-sm">{p.id}</span>
              <span className="font-data text-sm">
                weight &times; {p.factor}
              </span>
            </div>
            <p className="mt-1 text-sm">{p.detects}</p>
            <p className="mt-1 text-sm text-ink/70">{p.why}</p>
          </li>
        ))}
      </ul>
      <p className="mt-4 text-sm text-ink/80">
        <strong>Clusters vote once:</strong> {m.reputation.cluster_cap_rule}
      </p>
      <p className="mt-2 text-sm text-ink/80">
        <strong>When we publish no score at all:</strong> a score is only shown
        once at least {m.reputation.min_evidence_to_publish} full independent
        voice survives weighting. Below that the arithmetic would be almost
        entirely our prior, which is a guess about agents in general rather than
        evidence about this one. An agent with hundreds of reviews and no
        independent reviewer gets no score, and we say why.
      </p>

      <h2 className="font-display mt-10 text-2xl">How agents are ordered</h2>
      <p className="font-data mt-2 text-xs">{m.ranking.formula}</p>
      <p className="mt-2 text-sm text-ink/80">{m.ranking.default_filter}</p>

      <h2 className="font-display mt-10 text-2xl">
        What we put on chain, and how to check it
      </h2>
      <p className="mt-2 text-sm text-ink/80">{m.publication.what}</p>
      <p className="mt-3 text-sm text-ink/80">
        {m.publication.who_can_publish}
      </p>
      <p className="mt-3 text-sm text-ink/80">{m.publication.caveat}</p>
      <p className="mt-3 text-sm text-ink/80">{m.publication.how_to_check}</p>
      <p className="font-data mt-3 text-xs break-all text-ink/70">
        {m.publication.leaf_encoding}
      </p>
      <Row
        k="snapshot rebuilt every"
        v={`${m.publication.build_interval_secs / 60} minutes`}
      />

      <h2 className="font-display mt-10 text-2xl">How this can be wrong</h2>
      <ul className="mt-2 list-disc pl-5">
        {m.known_weaknesses.map((w) => (
          <li key={w} className="mt-2 text-sm text-ink/80">
            {w}
          </li>
        ))}
      </ul>

      <h2 className="font-display mt-10 text-2xl">Check it yourself</h2>
      <p className="mt-2 text-sm text-ink/80">
        The parameters above come from{" "}
        <a className="underline" href="/v1/methodology">
          the API
        </a>
        , the code that uses them is in the open, and every agent page links out
        to 8004scan and BscScan so you can compute the registry&apos;s own
        average yourself and compare it to ours.
      </p>
      <p className="font-data mt-6 text-xs text-dormant">
        We probe endpoints politely: one request every ten seconds per host,
        pooled for hosts serving many registrations, with a real user agent
        naming this project.
      </p>
    </main>
  );
}
