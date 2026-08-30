import { fetchStats } from "@/lib/api-server";

// Registry health. Every figure is our own measurement; where a published
// study is quoted it is named and dated and kept separate from our numbers.
export const dynamic = "force-dynamic";

function Big({
  value,
  of,
  label,
  detail,
}: {
  value: string;
  of?: string;
  label: string;
  detail: string;
}) {
  return (
    <div className="rounded-lg border border-dormant/40 p-4">
      <p className="eyebrow text-dormant">{label}</p>
      <p className="font-data mt-2 text-3xl">
        {value}
        {of ? <span className="text-dormant"> / {of}</span> : null}
      </p>
      <p className="mt-1 text-sm text-ink/80">{detail}</p>
    </div>
  );
}

function Bar({
  parts,
}: {
  parts: { label: string; value: number; className: string }[];
}) {
  const total = parts.reduce((a, p) => a + p.value, 0) || 1;
  return (
    <div>
      <div className="flex h-4 w-full overflow-hidden rounded">
        {parts.map((p) => (
          <div
            key={p.label}
            className={p.className}
            style={{ width: `${(p.value / total) * 100}%` }}
          />
        ))}
      </div>
      <ul className="font-data mt-2 flex flex-wrap gap-4 text-xs">
        {parts.map((p) => (
          <li key={p.label}>
            {p.label} {p.value.toLocaleString()}
          </li>
        ))}
      </ul>
    </div>
  );
}

export default async function StatsPage() {
  const stats = await fetchStats();

  // These two look the same on screen and are not the same thing. Saying
  // "nothing has been measured" when our API is simply unreachable blames
  // our own data for someone else's outage, and a reader cannot tell the
  // difference unless we do.
  if (!stats) {
    return (
      <main className="mx-auto max-w-[900px] px-8 py-16">
        <h1 className="font-display text-4xl">Registry health</h1>
        <p className="mt-4 max-w-xl text-sm text-flag">
          Our API is not answering, so this page has nothing to read. The
          measurements themselves are unaffected: they live in the database and
          this page will fill in again as soon as the API is back.
        </p>
        <nav className="mt-6 flex flex-wrap gap-3">
          <a
            href="/stats"
            className="rounded bg-ink px-4 py-2 text-sm text-paper hover:opacity-90"
          >
            Try again
          </a>
          <a
            href="/"
            className="rounded border border-dormant/50 px-4 py-2 text-sm hover:border-ink"
          >
            Back to the marketplace
          </a>
        </nav>
      </main>
    );
  }

  if (!stats.measured) {
    return (
      <main className="mx-auto max-w-[900px] px-8 py-16">
        <h1 className="font-display text-4xl">Registry health</h1>
        <p className="mt-4 max-w-xl text-sm text-ink/80">
          Nothing has been measured yet, so there is nothing to report. We would
          rather show you this than a page of zeroes.
        </p>
        <p className="mt-3 max-w-xl text-sm text-ink/70">
          The prober scores an agent once it has enough probes to judge fairly,
          so this page fills in after the first full pass rather than
          immediately.
        </p>
        <nav className="mt-6">
          <a
            href="/"
            className="rounded border border-dormant/50 px-4 py-2 text-sm hover:border-ink"
          >
            Back to the marketplace
          </a>
        </nav>
      </main>
    );
  }

  const answering = stats.live + stats.flaky;
  const answeringPct = ((answering / stats.registered) * 100).toFixed(2);
  const keptPct = ((stats.reviews_kept / stats.feedback) * 100).toFixed(1);
  const clusterPct = (
    (stats.largest_cluster_reviews / stats.feedback) *
    100
  ).toFixed(1);

  return (
    <main className="mx-auto max-w-[900px] px-8 py-16">
      <a href="/" className="eyebrow text-dormant hover:text-ink">
        &larr; ALL AGENTS
      </a>
      <h1 className="font-display mt-3 text-4xl">Registry health</h1>
      <p className="mt-4 max-w-2xl text-base">
        What the ERC-8004 registry on BNB Smart Chain actually contains, as
        measured by our own indexer and prober. Nothing on this page is taken
        from anyone else&apos;s dashboard.
      </p>

      <section className="mt-10">
        <p className="eyebrow text-dormant">DOES ANYONE ANSWER</p>
        <div className="mt-3 grid grid-cols-1 gap-4 sm:grid-cols-3">
          <Big
            label="REGISTERED"
            value={stats.registered.toLocaleString()}
            detail="agents minted on the Identity Registry"
          />
          <Big
            label="DECLARE AN ENDPOINT"
            value={stats.with_endpoints.toLocaleString()}
            detail="the rest name nowhere to call at all"
          />
          <Big
            label="ANSWER WHEN CALLED"
            value={answering.toLocaleString()}
            detail={`${answeringPct} percent of everything registered`}
          />
        </div>
        <div className="mt-6">
          <Bar
            parts={[
              { label: "live", value: stats.live, className: "bg-signal" },
              { label: "flaky", value: stats.flaky, className: "bg-signal/50" },
              { label: "down", value: stats.down, className: "bg-flag/60" },
              {
                label: "still measuring",
                value: stats.measuring,
                className: "bg-dormant/40",
              },
            ]}
          />
        </div>
        <p className="mt-4 max-w-2xl text-sm text-ink/80">
          Based on {stats.probes_total.toLocaleString()} probes we have sent and
          kept. An agent is only given a status once it has been probed enough
          times to judge fairly, so the measuring bar is agents we have not
          finished assessing, not agents we are accusing of anything.
        </p>
      </section>

      <section className="mt-12">
        <p className="eyebrow text-dormant">IS THE PRAISE REAL</p>
        <div className="mt-3 grid grid-cols-1 gap-4 sm:grid-cols-3">
          <Big
            label="REVIEWS ON CHAIN"
            value={stats.feedback.toLocaleString()}
            detail={`written by just ${stats.reviewers} distinct addresses`}
          />
          <Big
            label="INDEPENDENT VOICES"
            value={stats.reviews_kept.toLocaleString()}
            detail={`${keptPct} percent survive reviewer weighting`}
          />
          <Big
            label="AGENTS WE CAN SCORE"
            value={stats.agents_scored.toLocaleString()}
            of={stats.agents_rated.toLocaleString()}
            detail="the rest have reviews, but none independent enough to count"
          />
        </div>
        <p className="mt-6 max-w-2xl text-sm text-ink/80">
          The single largest funding cluster is{" "}
          <span className="font-data">{stats.largest_cluster_reviewers}</span>{" "}
          addresses whose first transaction was paid for by the same wallet.
          Between them they wrote{" "}
          <span className="font-data">
            {stats.largest_cluster_reviews.toLocaleString()}
          </span>{" "}
          reviews, which is <span className="font-data">{clusterPct}</span>{" "}
          percent of every review on the registry. That is one operator, not a
          community.
        </p>
        <p className="mt-3 max-w-2xl text-sm text-ink/80">
          Only <span className="font-data">{stats.reviewers_independent}</span>{" "}
          of the {stats.reviewers} reviewing addresses carry full weight after
          every check. The rules that decide this are published in full on{" "}
          <a className="underline" href="/methodology">
            the methodology page
          </a>
          , including the ways they can be wrong.
        </p>
      </section>

      <section className="mt-12">
        <p className="eyebrow text-dormant">WHAT WE CANNOT CLAIM</p>
        <p className="mt-3 max-w-2xl text-sm text-ink/80">
          We measure reachability from one place, so an endpoint that answers
          elsewhere but not to us reads as down. We cannot see inside an agent
          to know whether it does its job well; a live endpoint and an
          independent review are evidence, not a guarantee. Our reviewer
          weighting catches operators who fund their reviewers from one wallet
          and who rate the same agents together, and it would miss a patient
          operator who funded each address separately.
        </p>
        <p className="mt-3 max-w-2xl text-sm text-ink/80">
          For corroboration from outside this project, arXiv:2606.26028 version
          2 studied the same registries through 13 May 2026 and reported that 4
          percent of BSC registrations exposed a live service endpoint and that
          59.2 percent of BSC reviewers showed coordinated behaviour. Those are
          their numbers on their data window, not ours. Our figures above are
          measured today and are our own.
        </p>
      </section>

      <p className="font-data mt-12 text-xs text-dormant">
        indexed to block {stats.indexed_to_block?.toLocaleString() ?? "n/a"} ·
        scored {stats.computed_at?.slice(0, 16).replace("T", " ")}Z
      </p>
    </main>
  );
}
