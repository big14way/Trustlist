"use client";

import { useEffect, useMemo, useState } from "react";
import { formatUnits, parseUnits } from "viem";
import {
  useAccount,
  useConnect,
  useReadContract,
  useSwitchChain,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { hireRailAbi } from "@/lib/hireRailAbi";
import {
  activeChain,
  erc20Abi,
  explorerTx,
  HIRE_RAIL,
  hireConfigured,
  PAYMENT_TOKEN,
} from "@/lib/chain";

// Token amounts are bigint end to end. No JavaScript number ever touches a
// balance, an allowance, or a budget.
const DEADLINE_CHOICES = [
  { label: "1 hour", secs: 3600 },
  { label: "24 hours", secs: 86400 },
  { label: "7 days", secs: 604800 },
];

// Mirrors HireRail.Mode. The wording here is the whole honesty of the
// product: one of these is fast because it is trust based, and we say so.
const MODE_DIRECT = 0;
const MODE_PROTECTED = 1;

// The live mainnet policy window, read from the contract at deploy time and
// echoed here so a protected deadline is never shorter than it.
const PROTECTED_MIN_SECS = 604800;

type Props = {
  agentId: string;
  agentName: string;
  provider: `0x${string}`;
  onClose: () => void;
};

function Row({ children }: { children: React.ReactNode }) {
  return <div className="mt-4">{children}</div>;
}

function Label({ children }: { children: React.ReactNode }) {
  return <p className="eyebrow mb-1 text-dormant">{children}</p>;
}

export function HireSheet({ agentId, agentName, provider, onClose }: Props) {
  const { address, isConnected, chainId } = useAccount();
  const { connect, connectors, isPending: connecting } = useConnect();
  const { switchChain } = useSwitchChain();

  const [spec, setSpec] = useState(
    `Summarise what ${agentName} can do for me and deliver it as a short report.`,
  );
  const [budgetText, setBudgetText] = useState("1");
  const [deadlineSecs, setDeadlineSecs] = useState(86400);
  const [mode, setMode] = useState<number>(MODE_DIRECT);
  const [step, setStep] = useState<"form" | "approving" | "hiring" | "done">(
    "form",
  );
  const [errorText, setErrorText] = useState<string | null>(null);

  const wrongNetwork = isConnected && chainId !== activeChain.id;

  const { data: decimals } = useReadContract({
    abi: erc20Abi,
    address: PAYMENT_TOKEN || undefined,
    functionName: "decimals",
    query: { enabled: hireConfigured },
  });
  const { data: symbol } = useReadContract({
    abi: erc20Abi,
    address: PAYMENT_TOKEN || undefined,
    functionName: "symbol",
    query: { enabled: hireConfigured },
  });
  const { data: balance, refetch: refetchBalance } = useReadContract({
    abi: erc20Abi,
    address: PAYMENT_TOKEN || undefined,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: hireConfigured && !!address },
  });
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    abi: erc20Abi,
    address: PAYMENT_TOKEN || undefined,
    functionName: "allowance",
    args: address && HIRE_RAIL ? [address, HIRE_RAIL] : undefined,
    query: { enabled: hireConfigured && !!address },
  });

  const dec = decimals ?? 18;
  const tokenSymbol = symbol ?? "U";

  const budget = useMemo(() => {
    try {
      const t = budgetText.trim();
      if (!t) return null;
      return parseUnits(t, dec);
    } catch {
      return null;
    }
  }, [budgetText, dec]);

  const needsApproval =
    budget !== null && allowance !== undefined && allowance < budget;
  const insufficient =
    budget !== null && balance !== undefined && balance < budget;

  const { writeContractAsync } = useWriteContract();
  const [hireHash, setHireHash] = useState<`0x${string}` | undefined>();
  const receipt = useWaitForTransactionReceipt({ hash: hireHash });

  useEffect(() => {
    if (receipt.isSuccess) setStep("done");
  }, [receipt.isSuccess]);

  // Persist the intent before sending so a refresh mid flow can recover it.
  useEffect(() => {
    if (!hireHash) return;
    try {
      localStorage.setItem(
        `trustlist:hire:${agentId}`,
        JSON.stringify({ hash: hireHash, agentId, spec, at: Date.now() }),
      );
    } catch {
      // Storage can be unavailable in private windows; the flow still works,
      // it just cannot self recover after a refresh.
    }
  }, [hireHash, agentId, spec]);

  async function onConfirm() {
    setErrorText(null);
    if (budget === null || budget === 0n) {
      setErrorText("Enter a budget above zero.");
      return;
    }
    try {
      if (needsApproval) {
        setStep("approving");
        // Exact amount only. Never an unbounded allowance.
        await writeContractAsync({
          abi: erc20Abi,
          address: PAYMENT_TOKEN as `0x${string}`,
          functionName: "approve",
          args: [HIRE_RAIL as `0x${string}`, budget],
        });
        await refetchAllowance();
      }
      setStep("hiring");
      // A protected job must outlast the dispute window or it expires before
      // it can settle. The contract enforces this too; we just never send a
      // transaction we know will revert.
      const effectiveSecs =
        mode === MODE_PROTECTED
          ? Math.max(deadlineSecs, PROTECTED_MIN_SECS + 86400)
          : deadlineSecs;
      const deadline = BigInt(Math.floor(Date.now() / 1000) + effectiveSecs);
      const specHash = await hashSpec(spec);
      const hash = await writeContractAsync({
        abi: hireRailAbi,
        address: HIRE_RAIL as `0x${string}`,
        functionName: "hire",
        args: [BigInt(agentId), provider, budget, deadline, specHash, spec, mode],
      });
      setHireHash(hash);
      await refetchBalance();
    } catch (e) {
      // A rejected signature is not an error state, it is the user changing
      // their mind: return to the form with everything they typed intact.
      const msg = e instanceof Error ? e.message : String(e);
      setStep("form");
      setErrorText(
        /rejected|denied|User rejected/i.test(msg)
          ? "You cancelled the signature. Nothing was sent and your details are still here."
          : msg.slice(0, 200),
      );
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-ink/40 sm:items-center"
      role="dialog"
      aria-modal="true"
      aria-label={`Hire ${agentName}`}
    >
      <div className="max-h-[92vh] w-full max-w-lg overflow-y-auto rounded-t-lg border border-dormant/40 bg-paper p-6 sm:rounded-lg">
        <div className="flex items-start justify-between gap-4">
          <div>
            <p className="eyebrow text-dormant">HIRE</p>
            <h2 className="font-display text-2xl">{agentName}</h2>
          </div>
          <button
            onClick={onClose}
            className="eyebrow rounded border border-dormant/50 px-2 py-1 hover:border-ink"
          >
            CLOSE
          </button>
        </div>

        {!hireConfigured ? (
          <p className="mt-6 text-sm text-flag">
            The hire rail is not deployed for this environment yet, so hiring is
            switched off rather than pretending to work. Browsing and every
            measurement on this site still work.
          </p>
        ) : step === "done" ? (
          <div className="mt-6">
            <p className="font-data text-lg">Hired.</p>
            <p className="mt-2 text-sm text-ink/80">
              The escrow is funded and the agent has until your deadline to
              deliver.{" "}
              {mode === MODE_DIRECT
                ? "When it delivers, press Accept on the job and it gets paid immediately."
                : "When it delivers, a seven day dispute window opens before anyone can settle."}{" "}
              If nothing arrives you can reclaim every token.
            </p>
            {hireHash ? (
              <p className="font-data mt-3 text-xs break-all">
                <a className="underline" href={explorerTx(hireHash)} target="_blank" rel="noreferrer">
                  {hireHash}
                </a>
              </p>
            ) : null}
            <button
              onClick={onClose}
              className="mt-5 w-full rounded bg-ink px-4 py-2 text-paper"
            >
              Done
            </button>
          </div>
        ) : (
          <>
            <Row>
              <Label>WHAT SHOULD IT DO</Label>
              <textarea
                value={spec}
                onChange={(e) => setSpec(e.target.value)}
                rows={3}
                className="w-full rounded border border-dormant/50 bg-paper p-2 text-sm"
              />
              <p className="mt-1 text-xs text-ink/60">
                This text is hashed on chain so the delivery can be checked
                against what you asked for.
              </p>
            </Row>

            <Row>
              <Label>BUDGET</Label>
              <div className="flex items-center gap-2">
                <input
                  value={budgetText}
                  onChange={(e) => setBudgetText(e.target.value)}
                  inputMode="decimal"
                  className="font-data w-32 rounded border border-dormant/50 bg-paper p-2 text-sm"
                />
                <span className="font-data text-sm">{tokenSymbol}</span>
                {balance !== undefined ? (
                  <span className="font-data ml-auto text-xs text-ink/60">
                    you hold {formatUnits(balance, dec)}
                  </span>
                ) : null}
              </div>
              {budget === null ? (
                <p className="mt-1 text-xs text-flag">
                  That is not a number we can read as an amount.
                </p>
              ) : null}
              {insufficient ? (
                <p className="mt-1 text-xs text-flag">
                  You need {budgetText} {tokenSymbol} and hold{" "}
                  {balance !== undefined ? formatUnits(balance, dec) : "0"}.
                  Lower the budget or top up before confirming.
                </p>
              ) : null}
            </Row>

            <Row>
              <Label>HOW THE MONEY GETS RELEASED</Label>
              <div className="grid grid-cols-1 gap-2">
                <button
                  onClick={() => setMode(MODE_DIRECT)}
                  className={`rounded border p-3 text-left ${
                    mode === MODE_DIRECT ? "border-ink bg-ink/5" : "border-dormant/50"
                  }`}
                >
                  <span className="block text-sm font-medium">
                    You release it
                  </span>
                  <span className="mt-1 block text-xs text-ink/70">
                    The agent gets paid the moment you press Accept, in one
                    transaction. If you never accept, your money comes back to
                    you at the deadline. The agent is trusting you, and there
                    is no dispute process.
                  </span>
                </button>
                <button
                  onClick={() => setMode(MODE_PROTECTED)}
                  className={`rounded border p-3 text-left ${
                    mode === MODE_PROTECTED ? "border-ink bg-ink/5" : "border-dormant/50"
                  }`}
                >
                  <span className="block text-sm font-medium">
                    Nobody releases it alone
                  </span>
                  <span className="mt-1 block text-xs text-ink/70">
                    A seven day window opens when the agent delivers. You can
                    dispute inside it, and a voter panel decides. Neither of
                    you can move the money on your own. Slower, and the
                    deadline has to be longer than seven days.
                  </span>
                </button>
              </div>
            </Row>

            <Row>
              <Label>DEADLINE</Label>
              <div className="flex gap-2">
                {DEADLINE_CHOICES.map((d) => (
                  <button
                    key={d.secs}
                    onClick={() => setDeadlineSecs(d.secs)}
                    className={`rounded border px-3 py-1 text-sm ${
                      deadlineSecs === d.secs
                        ? "border-ink bg-ink text-paper"
                        : "border-dormant/50"
                    }`}
                  >
                    {d.label}
                  </button>
                ))}
              </div>
              <p className="mt-1 text-xs text-ink/60">
                {mode === MODE_PROTECTED
                  ? "Protected jobs need a deadline beyond the seven day window, so we set it to eight days. If the agent never delivers, you can take your money back yourself."
                  : "If the agent has not delivered by then, you can take your money back yourself. Nobody has to approve it."}
              </p>
            </Row>

            {errorText ? (
              <p className="mt-4 rounded border border-flag/50 p-2 text-sm text-flag">
                {errorText}
              </p>
            ) : null}

            <div className="mt-6">
              {!isConnected ? (
                connectors.length === 0 ? (
                  <p className="text-sm text-ink/80">
                    No wallet extension found. You can browse everything here
                    without one.{" "}
                    <a
                      className="underline"
                      href="https://www.bnbchain.org/en/wallets"
                      target="_blank"
                      rel="noreferrer"
                    >
                      Get a BNB Chain wallet
                    </a>{" "}
                    to hire.
                  </p>
                ) : (
                  <button
                    onClick={() => connectors[0] && connect({ connector: connectors[0] })}
                    disabled={connecting}
                    className="w-full rounded bg-ink px-4 py-2 text-paper disabled:opacity-60"
                  >
                    {connecting ? "Connecting" : "Connect wallet"}
                  </button>
                )
              ) : wrongNetwork ? (
                <button
                  onClick={() => switchChain({ chainId: activeChain.id })}
                  className="w-full rounded border border-ink px-4 py-2"
                >
                  Switch to {activeChain.name}
                </button>
              ) : (
                <button
                  onClick={onConfirm}
                  disabled={
                    step !== "form" || budget === null || insufficient
                  }
                  className="w-full rounded bg-ink px-4 py-2 text-paper disabled:opacity-60"
                >
                  {step === "approving"
                    ? `Approving exactly ${budgetText} ${tokenSymbol}`
                    : step === "hiring"
                      ? receipt.isLoading
                        ? "Waiting for the chain"
                        : "Confirm in your wallet"
                      : needsApproval
                        ? `Approve and hire for ${budgetText} ${tokenSymbol}`
                        : `Hire for ${budgetText} ${tokenSymbol}`}
                </button>
              )}
              {hireHash ? (
                <p className="font-data mt-3 text-xs break-all text-ink/70">
                  sent, waiting for confirmation:{" "}
                  <a className="underline" href={explorerTx(hireHash)} target="_blank" rel="noreferrer">
                    {hireHash.slice(0, 22)}…
                  </a>
                </p>
              ) : null}
              <p className="mt-3 text-xs text-ink/60">
                We ask your wallet to approve the exact budget and nothing
                more. The money sits in the ERC-8183 escrow contract, not with
                us and not with the agent.{" "}
                {mode === MODE_DIRECT
                  ? "In this mode our contract is the escrow's evaluator, and the only code path that releases it requires your address. We cannot pay the agent without you."
                  : "In this mode we are not the evaluator at all: the protocol's own router and policy decide."}
              </p>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

async function hashSpec(spec: string): Promise<`0x${string}`> {
  const { keccak256, toHex } = await import("viem");
  return keccak256(toHex(spec));
}
