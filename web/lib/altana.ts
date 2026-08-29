"use client";

import {
  BNB,
  BNB_TESTNET,
  createClient as createAltanaClient,
  signerFromPasskey,
  type PasskeyCredential,
  type SessionPermissions,
} from "@altananetwork/sdk";
import { HIRE_RAIL, PAYMENT_TOKEN } from "@/lib/chain";

// Which Altana deployment we talk to. Both are real full stacks: chain 56 and
// chain 97 each have their own keystore, account contracts, and relay.
const CHAIN_ID = Number(process.env.NEXT_PUBLIC_ALTANA_CHAIN_ID ?? "56");
export const altanaNetwork = CHAIN_ID === 97 ? BNB_TESTNET : BNB;

/// Altana is available when we know which HireRail a session should be
/// allowed to call. A session with no target to scope to would have to be
/// granted over every contract on the chain, which is the opposite of the
/// point.
export const altanaConfigured = HIRE_RAIL !== "" && PAYMENT_TOKEN !== "";

export function altanaClient() {
  return createAltanaClient({ chains: [altanaNetwork] });
}

export const SPEND_PERIODS = ["hour", "day", "week"] as const;
export type SpendPeriod = (typeof SPEND_PERIODS)[number];

/// What the agent is allowed to do with this session, and nothing else.
///
/// Two rules, both enforced on chain by the Altana account contract rather
/// than by us: it may only call HireRail, and it may only move up to `cap` of
/// the payment token in each rolling period. A call outside either rule
/// reverts at validation time, so the cap is not a promise we are making, it
/// is a constraint the chain applies.
export function hirePermissions(cap: bigint, period: SpendPeriod): SessionPermissions {
  return {
    calls: [{ to: HIRE_RAIL as `0x${string}` }],
    spend: [
      {
        limit: cap,
        period,
        token: PAYMENT_TOKEN as `0x${string}`,
      },
    ],
  };
}

// ---------------------------------------------------------------------------
// What we persist
//
// Nothing secret. The wallet's authority is a passkey, so the private half
// never leaves the device's authenticator: we could not store it if we wanted
// to. What is kept here is the credential's public half plus the session
// metadata needed to show a cap, show an expiry, and revoke. Revocation needs
// the session's public key and the admin passkey, so a browser that has this
// record can always revoke, and a browser that does not can never spend.
// ---------------------------------------------------------------------------

const WALLET_KEY = "trustlist.altana.wallet";
const SESSIONS_KEY = "trustlist.altana.sessions";

export type StoredWallet = {
  address: `0x${string}`;
  credential: PasskeyCredential;
  createdAt: number;
};

export type StoredSession = {
  publicKey: `0x${string}`;
  walletAddress: `0x${string}`;
  cap: string;
  period: SpendPeriod;
  expiry: number;
  grantedAt: number;
  grantTx?: `0x${string}`;
  revokedTx?: `0x${string}`;
  revokedAt?: number;
};

function read<T>(key: string, fallback: T): T {
  if (typeof window === "undefined") return fallback;
  try {
    const raw = window.localStorage.getItem(key);
    return raw === null ? fallback : (JSON.parse(raw) as T);
  } catch {
    // A browser that refuses storage still gets a working page, it just
    // cannot remember a session between visits.
    return fallback;
  }
}

function write(key: string, value: unknown): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // Nothing to do. The grant still happened on chain, which is the record
    // that matters.
  }
}

export function loadWallet(): StoredWallet | null {
  return read<StoredWallet | null>(WALLET_KEY, null);
}

export function saveWallet(wallet: StoredWallet): void {
  write(WALLET_KEY, wallet);
}

export function loadSessions(): StoredSession[] {
  return read<StoredSession[]>(SESSIONS_KEY, []);
}

export function saveSession(session: StoredSession): void {
  const all = loadSessions().filter((s) => s.publicKey !== session.publicKey);
  write(SESSIONS_KEY, [session, ...all]);
}

export function markRevoked(publicKey: string, tx?: `0x${string}`): void {
  write(
    SESSIONS_KEY,
    loadSessions().map((s) =>
      s.publicKey === publicKey
        ? { ...s, revokedTx: tx, revokedAt: Math.floor(Date.now() / 1000) }
        : s,
    ),
  );
}

/// Live, expired, or revoked. Expiry is a chain enforced fact, so a session
/// that has run out is not "still there but ignored", it genuinely cannot
/// sign anything the account will accept.
export function sessionState(
  session: StoredSession,
  nowSecs: number,
): "live" | "expired" | "revoked" {
  if (session.revokedAt !== undefined) return "revoked";
  return session.expiry <= nowSecs ? "expired" : "live";
}

export function explorerAddress(address: string): string {
  return `${altanaNetwork.explorer}/address/${address}`;
}

export function explorerTxLink(hash: string): string {
  return `${altanaNetwork.explorer}/tx/${hash}`;
}

/// Create the wallet whose authority is a passkey on this device.
///
/// This goes through the SDK's own createPasskeyWallet rather than creating a
/// passkey and a wallet separately. EIP-7702 setCode needs a secp256k1
/// signature and a passkey is P256, so the SDK bootstraps with a one shot
/// throwaway key, bakes the resulting wallet address into the credential as
/// the WebAuthn user handle, and discards the throwaway. Doing those two
/// steps by hand gets the ordering wrong and loses the recovery path.
export async function createPasskeyWallet(name: string): Promise<StoredWallet> {
  const client = altanaClient();
  const wallet = await client.createPasskeyWallet({ name });
  const signer = wallet.signer;
  const stored: StoredWallet = {
    address: wallet.address,
    credential: signer.credential,
    createdAt: Math.floor(Date.now() / 1000),
  };
  saveWallet(stored);
  return stored;
}

export function signerFor(wallet: StoredWallet) {
  return signerFromPasskey(wallet.credential);
}
