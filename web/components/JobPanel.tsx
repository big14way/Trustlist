"use client";

import { formatUnits } from "viem";
import { useAccount, useWriteContract } from "wagmi";
import { useState } from "react";
import type { Job } from "@/lib/api";
import { hireRailAbi } from "@/lib/hireRailAbi";
import { explorerTx, HIRE_RAIL } from "@/lib/chain";

// The kernel's own job states. We render what the chain says, never a
// guess, and we say plainly what happens next in each one.
const STAGES = ["funded", "submitted", "completed"] as const;

function stageIndex(state: string): number {
  const i = STAGES.indexOf(state as (typeof STAGES)[number]);
  return i;
}

function whatHappensNext(job: Job): string {
  const deadline = job.deadline ? new Date(job.deadline) : null;
  const overdue = deadline !== null && deadline.getTime() < Date.now();
  switch (job.state) {
    case "funded":
      return overdue
        ? "The deadline passed without a delivery. You can take your money back now."
        : `Waiting on the agent. If nothing arrives by ${deadline?.toLocaleString() ?? "the deadline"}, you can reclaim every token yourself.`;
    case "submitted":
      return "The agent delivered. The dispute window is running: once it closes, anyone can settle the job and the agent gets paid.";
    case "completed":
      return "Settled. The agent has been paid from escrow.";
    case "rejected":
      return "The work was rejected. The escrow went back to you.";
    case "expired":
      return "Expired and refunded to you.";
    default:
      return "Waiting for the chain.";
  }
}

export function JobPanel({ job }: { job: Job }) {
  const { address } = useAccount();
  const { writeContractAsync } = useWriteContract();
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);

  const idx = stageIndex(job.state);
  const isMine =
    address !== undefined && address.toLowerCase() === job.hirer.toLowerCase();
  const deadline = job.deadline ? new Date(job.deadline) : null;
  const canReclaim =
    job.state === "funded" && deadline !== null && deadline.getTime() < Date.now();

  async function onReclaim() {
    setBusy(true);
    setNote(null);
    try {
      const hash = await writeContractAsync({
        abi: hireRailAbi,
        address: HIRE_RAIL as `0x${string}`,
        functionName: "reclaim",
        args: [BigInt(job.job_id)],
      });
      setNote(`Reclaim sent: ${hash}`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      setNote(
        /rejected|denied/i.test(msg)
          ? "You cancelled the signature. The escrow is untouched and still yours to reclaim."
          : msg.slice(0, 180),
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <li className="rounded-lg border border-dormant/40 p-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="font-display text-lg">
          <a href={`/agents/${job.agent_id}`} className="hover:underline">
            {job.agent_name ?? `Agent #${job.agent_id}`}
          </a>
        </h3>
        <span className="font-data text-sm">
          {formatUnits(BigInt(job.budget), 18)} escrowed
        </span>
      </div>

      <ol className="mt-3 flex items-center gap-1" aria-label="Job progress">
        {STAGES.map((s, i) => {
          const reached = idx >= i;
          const terminalElsewhere =
            job.state === "expired" || job.state === "rejected";
          return (
            <li key={s} className="flex flex-1 items-center gap-1">
              <span
                className={`h-1.5 flex-1 rounded ${
                  terminalElsewhere
                    ? "bg-dormant/40"
                    : reached
                      ? "bg-signal"
                      : "bg-dormant/30"
                }`}
              />
              <span className="eyebrow text-dormant">{s}</span>
            </li>
          );
        })}
      </ol>

      <p className="mt-3 text-sm text-ink/80">{whatHappensNext(job)}</p>

      {job.spec ? (
        <p className="mt-2 text-xs text-ink/60">Asked for: {job.spec}</p>
      ) : null}

      <p className="font-data mt-2 text-xs text-ink/60">
        JOB {job.job_id} · STATE {job.state.toUpperCase()} · CHAIN{" "}
        {job.chain_id}
        {job.create_tx ? (
          <>
            {" · "}
            <a
              className="underline"
              href={explorerTx(job.create_tx)}
              target="_blank"
              rel="noreferrer"
            >
              hire tx
            </a>
          </>
        ) : null}
        {job.settle_tx ? (
          <>
            {" · "}
            <a
              className="underline"
              href={explorerTx(job.settle_tx)}
              target="_blank"
              rel="noreferrer"
            >
              settle tx
            </a>
          </>
        ) : null}
      </p>

      {canReclaim && isMine ? (
        <button
          onClick={onReclaim}
          disabled={busy}
          className="mt-3 rounded border border-ink px-4 py-1.5 text-sm hover:bg-ink hover:text-paper disabled:opacity-60"
        >
          {busy ? "Reclaiming" : "Reclaim my escrow"}
        </button>
      ) : null}

      {note ? (
        <p className="font-data mt-2 text-xs break-all text-ink/70">{note}</p>
      ) : null}
    </li>
  );
}
