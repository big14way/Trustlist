import { notFound } from "next/navigation";
import { HireButton } from "@/components/HireButton";
import { ProbeStrip } from "@/components/ProbeStrip";
import { VerifyDrawer } from "@/components/VerifyDrawer";
import {
  fetchAgent,
  fetchAgentEndpoints,
  fetchAgentReviews,
  fetchAgentUptime,
} from "@/lib/api-server";
import type { AgentCard, EndpointState, Review, Reviews } from "@/lib/api";

export const dynamic = "force-dynamic";

function StatusPill({ status }: { status: AgentCard["status"] }) {
  const styles: Record<AgentCard["status"], string> = {
    live: "bg-signal text-ink",
    flaky: "bg-signal/50 text-ink",
    down: "bg-dormant/40 text-paper",
    dormant: "bg-dormant/40 text-paper",
    measuring: "border border-paper/40 text-paper",
  };
  return (
    <span
      className={`eyebrow inline-block rounded px-2 py-1 ${styles[status]}`}
    >
      {status}
    </span>
  );
}

function StatBlock({
  label,
  value,
  detail,
}: {
  label: string;
  value: string;
  detail: string;
}) {
  return (
    <div className="rounded-lg border border-dormant/40 p-4">
      <p className="eyebrow text-dormant">{label}</p>
      <p className="font-data mt-1 text-2xl">{value}</p>
      <p className="mt-1 text-xs text-ink/70">{detail}</p>
    </div>
  );
}

function EndpointRow({ e }: { e: EndpointState }) {
  const rate =
    e.probes_7d > 0
      ? `${Math.round((e.ok_7d / e.probes_7d) * 100)}%`
      : "no data";
  // A 401, 402, or 403 means the endpoint is answering and asking for
  // payment or a key, which is a working agent, not a dead one.
  const verdict =
    e.last_ok === null
      ? "not probed yet"
      : e.last_ok
        ? `answering ${e.last_http_status}`
        : `${e.last_failure_kind ?? "failed"}${e.last_http_status ? ` (${e.last_http_status})` : ""}`;
  return (
    <li className="border-t border-dormant/30 py-3">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <span className="font-data text-sm break-all">{e.url}</span>
        <span className="eyebrow rounded border border-dormant/50 px-1.5 py-0.5 text-dormant">
          {e.kind}
        </span>
      </div>
      <p className="font-data mt-1 text-xs text-ink/70">
        {verdict}
        {e.last_latency_ms !== null ? ` · ${e.last_latency_ms}ms` : ""} · {rate}{" "}
        over {e.probes_7d} probes · every{" "}
        {e.cadence_secs >= 86400
          ? `${Math.round(e.cadence_secs / 86400)}d`
          : `${Math.round(e.cadence_secs / 60)}min`}
      </p>
    </li>
  );
}

const FLAG_COPY: Record<string, string> = {
  funding_cluster: "one wallet paid for five or more reviewers",
  shared_funder: "shares a funder with another reviewer",
  coreview_ring: "reviews the same agents as several others, again and again",
  one_shot: "one review, and almost nothing else on chain",
  no_other_activity: "barely transacts outside the registry",
  single_value_only: "has never given a different score",
  fresh_address: "funded days before it started reviewing",
  reciprocal: "rates an agent whose owner rates one of theirs",
  high_revocation: "writes feedback and takes it back",
};

function ReviewerRow({ r }: { r: Review }) {
  const weight = r.weight ? parseFloat(r.weight) : null;
  const scaled = (parseFloat(r.value) / Math.pow(10, r.value_decimals)).toFixed(
    0,
  );
  return (
    <li className="border-t border-dormant/30 py-2">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <span className="font-data text-xs">
          {r.reviewer.slice(0, 10)}…{r.reviewer.slice(-4)}
        </span>
        <span className="font-data text-xs">
          gave {scaled} · counted{" "}
          <span className={weight !== null && weight < 0.5 ? "text-flag" : ""}>
            {weight !== null ? weight.toFixed(2) : "1.00"}
          </span>
        </span>
      </div>
      {r.flags.length > 0 ? (
        <p className="mt-1 text-xs text-ink/70">
          {r.flags.map((f) => FLAG_COPY[f] ?? f).join(" · ")}
        </p>
      ) : (
        <p className="mt-1 text-xs text-ink/60">
          no independence problems found
        </p>
      )}
      {r.funder ? (
        <p className="font-data mt-0.5 text-[11px] text-dormant">
          funded by {r.funder.slice(0, 10)}…{r.funder.slice(-4)}
        </p>
      ) : null}
    </li>
  );
}

function ReviewsPanel({ reviews }: { reviews: Reviews }) {
  if (reviews.total === 0) {
    return (
      <div className="rounded-lg border border-dormant/40 p-4">
        <p className="text-sm text-ink/80">
          No reviews on chain for this agent. It is ranked on measured uptime
          alone, which is the honest basis when nobody has vouched for it.
        </p>
      </div>
    );
  }

  const kept = reviews.kept ?? 0;
  // Show the reviewers who carry the most weight first: if any independent
  // voice exists, the reader should see it before the farm.
  const ranked = [...reviews.items]
    .sort((a, b) => parseFloat(b.weight ?? "1") - parseFloat(a.weight ?? "1"))
    .slice(0, 12);

  return (
    <div>
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
        <div className="rounded-lg border border-dormant/40 p-4">
          <p className="eyebrow text-dormant">WHAT THE REGISTRY SAYS</p>
          <p className="font-data mt-2 text-3xl">
            {reviews.raw_average ?? "n/a"}
          </p>
          <p className="mt-1 text-sm text-ink/80">
            the plain average of {reviews.total} reviews, exactly as anyone
            reading the chain would compute it
          </p>
          <p className="font-data mt-3 text-xs text-ink/70">
            {reviews.total} REVIEWS FROM {reviews.distinct_reviewers} ADDRESSES
          </p>
        </div>

        <div
          className={`rounded-lg border p-4 ${
            kept === 0 ? "border-flag/60" : "border-dormant/40"
          }`}
        >
          <p className={`eyebrow ${kept === 0 ? "text-flag" : "text-dormant"}`}>
            WHAT WE COUNT
          </p>
          <p className="font-data mt-2 text-3xl">
            {reviews.trust ?? <span className="text-dormant">none</span>}
          </p>
          <p className="mt-1 text-sm text-ink/80">
            {kept === 0
              ? `${reviews.total} reviews, none of them from an independent address. We will not turn that into a score.`
              : `weighted by how independent each reviewer actually is, from ${kept} independent ${kept === 1 ? "voice" : "voices"}.`}
          </p>
          <p className="font-data mt-3 text-xs text-ink/70">
            KEPT {kept}/{reviews.total} · CONFIDENCE {reviews.confidence ?? "0"}
          </p>
        </div>
      </div>

      <details className="mt-4 rounded-lg border border-dormant/40 p-4">
        <summary className="cursor-pointer text-sm">
          Show every reviewer and why we weighted it that way
        </summary>
        <ul className="mt-2">
          {ranked.map((r, i) => (
            <ReviewerRow key={`${r.tx_hash}-${i}`} r={r} />
          ))}
        </ul>
        {reviews.items.length > ranked.length ? (
          <p className="font-data mt-2 text-xs text-dormant">
            showing {ranked.length} of {reviews.items.length} fetched
          </p>
        ) : null}
        <p className="mt-3 text-xs text-ink/70">
          Weights come from public chain data by published rules. See{" "}
          <a className="underline" href="/methodology">
            the methodology
          </a>
          .
        </p>
      </details>
    </div>
  );
}

export default async function AgentDetail({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const agent = await fetchAgent(id);
  if (!agent) notFound();

  const [uptime, endpoints, reviews] = await Promise.all([
    fetchAgentUptime(id),
    fetchAgentEndpoints(id),
    fetchAgentReviews(id),
  ]);

  const uptimePct = agent.uptime_7d
    ? `${(parseFloat(agent.uptime_7d) * 100).toFixed(1)}%`
    : "measuring";
  const liveness = agent.liveness
    ? parseFloat(agent.liveness).toFixed(1)
    : "measuring";
  const registered = new Date(agent.registered_at).toISOString().slice(0, 10);

  return (
    <main>
      <header className="bg-depth px-8 py-10 text-paper">
        <div className="mx-auto max-w-[1200px]">
          <a href="/" className="eyebrow text-paper/60 hover:text-paper">
            &larr; ALL AGENTS
          </a>
          <div className="mt-3 flex flex-wrap items-start justify-between gap-3">
            <h1 className="font-display text-4xl">
              {agent.name ?? `Agent #${agent.agent_id}`}
            </h1>
            <div className="flex items-center gap-3">
              <StatusPill status={agent.status} />
              <HireButton
                agentId={agent.agent_id}
                agentName={agent.name ?? `Agent ${agent.agent_id}`}
                provider={agent.owner}
              />
            </div>
          </div>
          <p className="font-data mt-3 text-xs text-paper/70">
            ID {agent.agent_id} · OWNER {agent.owner.slice(0, 10)}…
            {agent.owner.slice(-6)} · REGISTERED {registered}
          </p>
          {agent.description ? (
            <p className="mt-4 max-w-2xl text-sm text-paper/90">
              {agent.description}
            </p>
          ) : null}
        </div>
      </header>

      <div className="mx-auto max-w-[1200px] px-8 py-10">
        <section aria-label="Uptime history">
          <p className="eyebrow text-dormant">PROBE HISTORY, 7 DAYS BY HOUR</p>
          <div className="mt-3">
            <ProbeStrip
              buckets={uptime?.buckets ?? []}
              label={agent.name ?? `Agent ${agent.agent_id}`}
            />
          </div>
          <p className="font-data mt-2 text-xs text-dormant">
            amber answered · grey did not · hollow no probe that hour
          </p>
        </section>

        <section
          aria-label="Scores"
          className="mt-10 grid grid-cols-1 gap-4 sm:grid-cols-3"
        >
          <StatBlock
            label="LIVENESS"
            value={liveness}
            detail={`uptime ${uptimePct} over ${agent.probes_7d ?? 0} probes${
              agent.median_latency_ms
                ? `, median ${agent.median_latency_ms}ms`
                : ""
            }`}
          />
          <StatBlock
            label="TRUST"
            value={agent.trust ?? "not scored"}
            detail={
              agent.trust
                ? `from ${agent.feedback_kept ?? 0} independent voices out of ${agent.feedback_total} reviews, confidence ${agent.trust_confidence ?? "0"}`
                : `${agent.feedback_total} reviews on chain, none of them independent enough to score. Ranked on measured uptime instead.`
            }
          />
          <StatBlock
            label="JOBS"
            value={String(agent.jobs_completed)}
            detail={`${agent.jobs_disputed} disputed. Hiring through our rail is being wired up now.`}
          />
        </section>

        <section aria-label="Verify" className="mt-6">
          <VerifyDrawer agentId={agent.agent_id} />
        </section>

        <section aria-label="Reviews" className="mt-10">
          <p className="eyebrow text-dormant">REVIEWS</p>
          <div className="mt-3">
            {reviews ? (
              <ReviewsPanel reviews={reviews} />
            ) : (
              <p className="text-sm text-ink/70">
                Reviews could not be loaded.
              </p>
            )}
          </div>
        </section>

        <section aria-label="Endpoints" className="mt-10">
          <p className="eyebrow text-dormant">
            DECLARED ENDPOINTS AND WHAT WE LAST SAW
          </p>
          {endpoints && endpoints.items.length > 0 ? (
            <ul className="mt-2">
              {endpoints.items.map((e) => (
                <EndpointRow key={e.url} e={e} />
              ))}
            </ul>
          ) : (
            <p className="mt-2 text-sm text-ink/70">
              This agent&apos;s card declares no reachable endpoint, so there is
              nothing for us to probe. That is why it is ranked as dormant.
            </p>
          )}
        </section>

        <section aria-label="Cross checks" className="mt-10">
          <p className="eyebrow text-dormant">CHECK US</p>
          <p className="mt-2 text-sm text-ink/80">
            Every number here comes from our own indexer and prober. Verify the
            same agent somewhere else:
          </p>
          <ul className="font-data mt-2 flex flex-wrap gap-4 text-sm">
            <li>
              <a
                className="underline"
                href={`https://8004scan.io/agents/bsc/${agent.agent_id}`}
                target="_blank"
                rel="noreferrer"
              >
                8004scan
              </a>
            </li>
            <li>
              <a
                className="underline"
                href={`https://bscscan.com/token/0x8004A169FB4a3325136EB29fA0ceB6D2e539a432?a=${agent.agent_id}`}
                target="_blank"
                rel="noreferrer"
              >
                BscScan
              </a>
            </li>
            <li>
              <a
                className="underline"
                href={`https://bscscan.com/address/${agent.owner}`}
                target="_blank"
                rel="noreferrer"
              >
                owner
              </a>
            </li>
          </ul>
        </section>
      </div>
    </main>
  );
}
