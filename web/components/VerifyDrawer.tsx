"use client";

import { useState } from "react";
import { createPublicClient, http } from "viem";
import { activeChain } from "@/lib/chain";
import { trustSnapshotAbi } from "@/lib/trustSnapshotAbi";
import { apiGet } from "@/lib/api";

const SNAPSHOT_ADDRESS = (process.env.NEXT_PUBLIC_TRUST_SNAPSHOT ?? "") as
  `0x${string}` | "";

type ProofResponse = {
  snapshot_id: number;
  agent_id: string;
  merkle_root: string;
  leaf: string;
  index: number;
  proof: string[];
  verify_args: {
    agentId: string;
    liveness: number;
    trust: number;
    confidence: number;
    computedAt: number;
  };
};

type PublishedSnapshot = {
  id: number;
  merkle_root: string | null;
  agent_count: number;
  computed_at: number | null;
  onchain_index: number | null;
  contract: string | null;
};

type Result = {
  onChainRoot: string;
  servedRoot: string;
  proofNodes: number;
  index: number;
  honest: boolean;
  tampered: boolean;
  args: ProofResponse["verify_args"];
  publishedAt: number | null;
};

/// Check one agent's published scores against the contract, in the reader's
/// own browser. Nothing here trusts our API: the proof comes from us, but the
/// answer comes from the chain, and the same call is run twice, once with the
/// real numbers and once with an inflated trust score that must fail.
export function VerifyDrawer({ agentId }: { agentId: string }) {
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<Result | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function run() {
    setBusy(true);
    setError(null);
    setResult(null);
    try {
      // The published snapshot, not the newest one. Scores move between
      // publications, so this is the only tree the chain can confirm.
      const latest = await apiGet<PublishedSnapshot>("/v1/snapshots/published");
      if (
        !latest ||
        latest.merkle_root === null ||
        latest.onchain_index === null
      ) {
        setError("No snapshot has been published on chain yet.");
        return;
      }
      const proof = await apiGet<ProofResponse>(
        `/v1/snapshots/${latest.id}/proof/${agentId}`,
      );
      if (!proof) {
        setError("This agent is not in the latest snapshot.");
        return;
      }

      const client = createPublicClient({
        chain: activeChain,
        transport: http(),
      });
      const index = BigInt(latest.onchain_index);
      const nodes = proof.proof as `0x${string}`[];
      const a = proof.verify_args;

      const onChain = (await client.readContract({
        address: SNAPSHOT_ADDRESS as `0x${string}`,
        abi: trustSnapshotAbi,
        functionName: "snapshots",
        args: [index],
      })) as readonly [string, bigint, number, string];

      const call = (trust: number) =>
        client.readContract({
          address: SNAPSHOT_ADDRESS as `0x${string}`,
          abi: trustSnapshotAbi,
          functionName: "verify",
          args: [
            index,
            BigInt(a.agentId),
            a.liveness,
            trust,
            a.confidence,
            BigInt(a.computedAt),
            nodes,
          ],
        }) as Promise<boolean>;

      const [honest, tampered] = await Promise.all([
        call(a.trust),
        // 10000 basis points is a perfect trust score. If the contract
        // accepted this, the proof would be worthless.
        call(10_000),
      ]);

      setResult({
        onChainRoot: onChain[0],
        servedRoot: proof.merkle_root,
        proofNodes: nodes.length,
        index: proof.index,
        honest,
        tampered,
        args: a,
        publishedAt: latest.computed_at,
      });
    } catch (e) {
      setError(
        e instanceof Error
          ? `Could not reach the contract: ${e.message}`
          : "Could not reach the contract.",
      );
    } finally {
      setBusy(false);
    }
  }

  if (SNAPSHOT_ADDRESS === "") {
    return (
      <div className="rounded-lg border border-dormant/40 p-4">
        <p className="eyebrow text-dormant">Verify on chain</p>
        <p className="mt-2 text-xs text-ink/70">
          No snapshot contract is configured for this deployment, so there is
          nothing to check against yet.
        </p>
      </div>
    );
  }

  return (
    <div className="rounded-lg border border-dormant/40 p-4">
      <div className="flex items-baseline justify-between gap-4">
        <p className="eyebrow text-dormant">Verify on chain</p>
        <button
          type="button"
          className="eyebrow rounded border border-dormant/50 px-2 py-1 hover:bg-dormant/10"
          onClick={() => {
            const next = !open;
            setOpen(next);
            if (next && !result) void run();
          }}
        >
          {open ? "hide" : "check this score"}
        </button>
      </div>

      {open && (
        <div className="mt-3 text-xs text-ink/80">
          <p>
            We publish a Merkle root of every measured score. Your browser asks
            the contract at{" "}
            <span className="font-data break-all">{SNAPSHOT_ADDRESS}</span>{" "}
            whether this agent&apos;s numbers are in it. Scores move between
            publications, so what is checked here is the last snapshot we put on
            chain, which can be older than the number shown above.
          </p>

          {busy && <p className="mt-3">Asking the chain...</p>}
          {error && <p className="mt-3 text-dormant">{error}</p>}

          {result && (
            <dl className="font-data mt-3 space-y-2">
              <div>
                <dt className="text-dormant">root stored on chain</dt>
                <dd className="break-all">{result.onChainRoot}</dd>
              </div>
              <div>
                <dt className="text-dormant">root we serve</dt>
                <dd className="break-all">
                  {result.servedRoot}
                  {result.servedRoot.toLowerCase() ===
                  result.onChainRoot.toLowerCase()
                    ? " (same)"
                    : " (does not match, do not trust this page)"}
                </dd>
              </div>
              <div>
                <dt className="text-dormant">proof</dt>
                <dd>
                  {result.proofNodes} hashes, leaf {result.index}
                  {` liveness ${result.args.liveness} trust ${result.args.trust} confidence ${result.args.confidence}`}
                </dd>
              </div>
              <div>
                <dt className="text-dormant">snapshot taken</dt>
                <dd>
                  {result.publishedAt
                    ? new Date(result.publishedAt * 1000).toISOString()
                    : "unknown"}
                </dd>
              </div>
              <div>
                <dt className="text-dormant">contract says</dt>
                <dd>
                  {result.honest
                    ? "these numbers are in the published snapshot"
                    : "these numbers are NOT in the published snapshot"}
                </dd>
              </div>
              <div>
                <dt className="text-dormant">
                  same proof, trust changed to 100
                </dt>
                <dd>
                  {result.tampered
                    ? "accepted, which would mean the proof is broken"
                    : "rejected, as it should be"}
                </dd>
              </div>
            </dl>
          )}
        </div>
      )}
    </div>
  );
}
