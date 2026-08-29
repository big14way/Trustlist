"use client";

import { useCallback, useEffect, useState } from "react";
import { createPublicClient, formatUnits, http, parseUnits } from "viem";
import {
  altanaClient,
  altanaConfigured,
  altanaNetwork,
  createPasskeyWallet,
  explorerAddress,
  explorerTxLink,
  hirePermissions,
  loadSessions,
  loadWallet,
  markRevoked,
  saveSession,
  sessionState,
  signerFor,
  SPEND_PERIODS,
  type SpendPeriod,
  type StoredSession,
  type StoredWallet,
} from "@/lib/altana";
import { HIRE_RAIL, PAYMENT_TOKEN } from "@/lib/chain";

const TOKEN_DECIMALS = 18;

const EXPIRY_CHOICES = [
  { label: "1 hour", secs: 3600 },
  { label: "24 hours", secs: 86400 },
  { label: "7 days", secs: 604800 },
];

/// Say which side failed, because "HTTP request failed" tells a user nothing
/// they can act on. Every session action goes through the Altana relay, so an
/// unreachable relay is the most likely cause and the one worth naming.
function describeFailure(e: unknown, what: string): string {
  const message = e instanceof Error ? e.message : String(e);
  const unreachable =
    /failed to fetch|network|timed? ?out|ERR_/i.test(message) &&
    /altana/i.test(message);
  if (unreachable) {
    return `${what} The Altana relay at ${altanaNetwork.relayUrl} did not answer. Sessions are granted and revoked through it, so nothing can change until it is reachable. Your wallet and any existing sessions are unaffected.`;
  }
  return `${what} ${message}`;
}

function formatWhen(secs: number): string {
  return new Date(secs * 1000).toISOString().replace("T", " ").slice(0, 16);
}

export function SessionsClient() {
  const [wallet, setWallet] = useState<StoredWallet | null>(null);
  const [sessions, setSessions] = useState<StoredSession[]>([]);
  const [balance, setBalance] = useState<bigint | null>(null);
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));

  const [cap, setCap] = useState("5");
  const [period, setPeriod] = useState<SpendPeriod>("day");
  const [expirySecs, setExpirySecs] = useState(86400);

  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);

  useEffect(() => {
    setWallet(loadWallet());
    setSessions(loadSessions());
    const t = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 10_000);
    return () => clearInterval(t);
  }, []);

  const refreshBalance = useCallback(async (address: `0x${string}`) => {
    try {
      const client = createPublicClient({
        chain: altanaNetwork.chain,
        transport: http(altanaNetwork.publicRpcUrl),
      });
      setBalance(await client.getBalance({ address }));
    } catch {
      setBalance(null);
    }
  }, []);

  useEffect(() => {
    if (wallet) void refreshBalance(wallet.address);
  }, [wallet, refreshBalance]);

  async function onCreateWallet() {
    setBusy("wallet");
    setError(null);
    try {
      const created = await createPasskeyWallet("TrustList agent wallet");
      setWallet(created);
      setNote(
        "Wallet created. Its only authority is the passkey you just made, which never leaves this device.",
      );
    } catch (e) {
      setError(describeFailure(e, "The wallet was not created."));
    } finally {
      setBusy(null);
    }
  }

  async function onGrant() {
    if (!wallet) return;
    setBusy("grant");
    setError(null);
    setNote(null);
    try {
      const capWei = parseUnits(cap, TOKEN_DECIMALS);
      const expiry = Math.floor(Date.now() / 1000) + expirySecs;
      const client = altanaClient();
      const granted = await client.grantSession({
        wallet: { address: wallet.address },
        signer: signerFor(wallet),
        expiry,
        permissions: hirePermissions(capWei, period),
      });

      const stored: StoredSession = {
        publicKey: granted.publicKey,
        walletAddress: wallet.address,
        cap: capWei.toString(),
        period,
        expiry,
        grantedAt: Math.floor(Date.now() / 1000),
        grantTx: granted.transactionHash,
      };
      saveSession(stored);
      setSessions(loadSessions());
      setNote("Session granted. The cap and expiry are on chain now.");
    } catch (e) {
      setError(
        balance === 0n
          ? "The grant needs gas and this wallet holds no BNB. The Altana relay only accepts the native token as its fee, so fund the address above and try again."
          : describeFailure(e, "The session was not granted."),
      );
    } finally {
      setBusy(null);
    }
  }

  async function onRevoke(session: StoredSession) {
    if (!wallet) return;
    setBusy(session.publicKey);
    setError(null);
    setNote(null);
    try {
      const client = altanaClient();
      const result = await client.revokeSession({
        wallet: { address: wallet.address },
        signer: signerFor(wallet),
        session: session.publicKey,
      });
      markRevoked(session.publicKey, result.transactionHash);
      setSessions(loadSessions());
      setNote("Revoked. The next spend from that key fails at validation.");
    } catch (e) {
      setError(describeFailure(e, "The session was not revoked, so it is still live."));
    } finally {
      setBusy(null);
    }
  }

  if (!altanaConfigured) {
    return (
      <section aria-label="Sessions" className="mt-8">
        <div className="rounded-lg border border-dormant/40 p-4">
          <p className="text-sm text-ink/70">
            Sessions need a deployed HireRail to scope themselves to. A session
            that could call anything would be the opposite of a spend cap, so
            there is nothing to show until the rail is deployed for this
            environment.
          </p>
        </div>
      </section>
    );
  }

  return (
    <section aria-label="Sessions" className="mt-8 space-y-6">
      <div className="rounded-lg border border-dormant/40 p-4">
        <p className="eyebrow text-dormant">THE WALLET</p>
        {wallet === null ? (
          <>
            <p className="mt-2 text-sm text-ink/80">
              An agent wallet whose only authority is a passkey on this device.
              There is no private key for us to store, or for anyone to take.
            </p>
            <button
              type="button"
              onClick={onCreateWallet}
              disabled={busy !== null}
              className="eyebrow mt-3 rounded border border-dormant/50 px-3 py-2 hover:border-ink disabled:opacity-50"
            >
              {busy === "wallet" ? "Creating" : "Create with a passkey"}
            </button>
          </>
        ) : (
          <dl className="font-data mt-2 space-y-1 text-xs">
            <div>
              <dt className="text-dormant">address</dt>
              <dd className="break-all">
                <a
                  className="underline"
                  href={explorerAddress(wallet.address)}
                  target="_blank"
                  rel="noreferrer"
                >
                  {wallet.address}
                </a>
              </dd>
            </div>
            <div>
              <dt className="text-dormant">gas balance</dt>
              <dd>
                {balance === null
                  ? "could not read"
                  : `${formatUnits(balance, 18)} ${altanaNetwork.chain.nativeCurrency.symbol}`}
              </dd>
            </div>
          </dl>
        )}
        {wallet !== null && balance === 0n ? (
          <p className="mt-3 text-xs text-flag">
            This wallet holds no {altanaNetwork.chain.nativeCurrency.symbol}.
            Granting a session is an on chain transaction and the Altana relay
            charges its fee in the native token only, so the grant will fail
            until the address is funded.
          </p>
        ) : null}
      </div>

      {wallet !== null ? (
        <div className="rounded-lg border border-dormant/40 p-4">
          <p className="eyebrow text-dormant">GRANT A SESSION</p>
          <p className="mt-2 text-sm text-ink/80">
            The session may call one contract, HireRail, and may move at most
            the cap you set in each period. Both limits are enforced by the
            account contract, not by us.
          </p>

          <div className="mt-4 grid gap-4 sm:grid-cols-3">
            <label className="block">
              <span className="eyebrow text-dormant">CAP</span>
              <input
                aria-label="Spend cap"
                value={cap}
                onChange={(e) => setCap(e.target.value)}
                inputMode="decimal"
                className="font-data mt-1 w-full rounded border border-dormant/50 bg-transparent px-2 py-1"
              />
            </label>
            <label className="block">
              <span className="eyebrow text-dormant">PER</span>
              <select
                aria-label="Spend period"
                value={period}
                onChange={(e) => setPeriod(e.target.value as SpendPeriod)}
                className="font-data mt-1 w-full rounded border border-dormant/50 bg-transparent px-2 py-1"
              >
                {SPEND_PERIODS.map((p) => (
                  <option key={p} value={p}>
                    {p}
                  </option>
                ))}
              </select>
            </label>
            <label className="block">
              <span className="eyebrow text-dormant">EXPIRES IN</span>
              <select
                aria-label="Expiry"
                value={expirySecs}
                onChange={(e) => setExpirySecs(Number(e.target.value))}
                className="font-data mt-1 w-full rounded border border-dormant/50 bg-transparent px-2 py-1"
              >
                {EXPIRY_CHOICES.map((c) => (
                  <option key={c.secs} value={c.secs}>
                    {c.label}
                  </option>
                ))}
              </select>
            </label>
          </div>

          <button
            type="button"
            onClick={onGrant}
            disabled={busy !== null}
            className="eyebrow mt-4 rounded border border-dormant/50 px-3 py-2 hover:border-ink disabled:opacity-50"
          >
            {busy === "grant" ? "Granting" : "Grant this session"}
          </button>
          <p className="font-data mt-2 text-xs text-dormant">
            scoped to {HIRE_RAIL}, paying in {PAYMENT_TOKEN}
          </p>
        </div>
      ) : null}

      {error !== null ? (
        <p role="alert" className="text-sm text-flag">
          {error}
        </p>
      ) : null}
      {note !== null ? <p className="text-sm text-ink/70">{note}</p> : null}

      <div>
        <p className="eyebrow text-dormant">SESSIONS</p>
        {sessions.length === 0 ? (
          <p className="mt-2 text-sm text-ink/70">
            No sessions yet. One will appear here the moment you grant it, with
            its cap, its expiry, and a button to end it.
          </p>
        ) : (
          <ul className="mt-3">
            {sessions.map((s) => {
              const state = sessionState(s, now);
              return (
                <li
                  key={s.publicKey}
                  className="border-t border-dormant/30 py-3"
                >
                  <div className="flex items-baseline justify-between gap-4">
                    <span className="eyebrow rounded border border-dormant/50 px-1.5 py-0.5 text-dormant">
                      {state}
                    </span>
                    {state === "live" ? (
                      <button
                        type="button"
                        onClick={() => onRevoke(s)}
                        disabled={busy !== null}
                        className="eyebrow rounded border border-dormant/50 px-2 py-1 hover:border-ink disabled:opacity-50"
                      >
                        {busy === s.publicKey ? "Revoking" : "Revoke now"}
                      </button>
                    ) : null}
                  </div>
                  <dl className="font-data mt-2 space-y-1 text-xs text-ink/80">
                    <div>
                      <dt className="text-dormant">cap</dt>
                      <dd>
                        {formatUnits(BigInt(s.cap), TOKEN_DECIMALS)} per{" "}
                        {s.period}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-dormant">expires</dt>
                      <dd>{formatWhen(s.expiry)} UTC</dd>
                    </div>
                    <div>
                      <dt className="text-dormant">key</dt>
                      <dd className="break-all">{s.publicKey}</dd>
                    </div>
                    {s.grantTx ? (
                      <div>
                        <dt className="text-dormant">granted</dt>
                        <dd className="break-all">
                          <a
                            className="underline"
                            href={explorerTxLink(s.grantTx)}
                            target="_blank"
                            rel="noreferrer"
                          >
                            {s.grantTx}
                          </a>
                        </dd>
                      </div>
                    ) : null}
                    {s.revokedTx ? (
                      <div>
                        <dt className="text-dormant">revoked</dt>
                        <dd className="break-all">
                          <a
                            className="underline"
                            href={explorerTxLink(s.revokedTx)}
                            target="_blank"
                            rel="noreferrer"
                          >
                            {s.revokedTx}
                          </a>
                        </dd>
                      </div>
                    ) : null}
                  </dl>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </section>
  );
}
