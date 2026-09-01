// Grant a scoped Altana session on mainnet, then revoke it, and keep the
// transaction hashes whatever else happens.
//
// The session lives on an Altana smart account whose authority is a passkey.
// scripts/altana_wallet.mjs created that wallet and proved it can be brought
// back, so the credential in .altana-wallet.json is enough to sign here.
//
// This spends real BNB. The relay takes its fee in the native token, so the
// wallet must hold gas before either call will go through.
//
// The one failure that costs money is a grant that broadcasts and then loses
// its hash: the page could error, the browser could close, localStorage could
// refuse to write. So the hash is treated the way scripts/chainlib.sh treats
// a transaction hash. Whatever the outcome, if anything was signed we print
// the wallet address and say to check the explorer before running again,
// rather than reporting a clean failure and inviting a second grant.
//
// Usage, from the repository root:
//   node scripts/altana_session.mjs grant  --cap 5 --expiry 3600 --yes
//   node scripts/altana_session.mjs revoke --yes
//   node scripts/altana_session.mjs both   --cap 5 --expiry 3600 --yes
//
// Environment: WEB (default https://trustlistapp.vercel.app)

import { chromium } from "../web/node_modules/playwright/index.mjs";
import { readFileSync, writeFileSync, existsSync, chmodSync } from "node:fs";

const WEB = process.env.WEB ?? "https://trustlistapp.vercel.app";
const STORE = process.env.ALTANA_WALLET_FILE ?? ".altana-wallet.json";
const WALLET_KEY = "trustlist.altana.wallet";
const SESSIONS_KEY = "trustlist.altana.sessions";

const mode = process.argv[2];
if (!["check", "grant", "revoke", "both"].includes(mode ?? "")) {
  console.error("usage: node scripts/altana_session.mjs check|grant|revoke|both [--cap N] [--expiry SECS] [--yes]");
  process.exit(2);
}

const argv = process.argv.slice(3);
const opt = (name, dflt) => {
  const i = argv.indexOf(name);
  return i === -1 ? dflt : argv[i + 1];
};
const CAP = opt("--cap", "5");
const EXPIRY = opt("--expiry", "3600");
const YES = argv.includes("--yes");

if (!existsSync(STORE)) {
  console.error(`${STORE} does not exist. Run scripts/altana_wallet.mjs create first.`);
  process.exit(1);
}
const saved = JSON.parse(readFileSync(STORE, "utf8"));

function save(sessions) {
  const next = { ...saved, sessions, updatedAt: new Date().toISOString() };
  writeFileSync(STORE, JSON.stringify(next, null, 2));
  chmodSync(STORE, 0o600);
}

// Every hash we ever see, so a crash after broadcast still leaves a record.
const seen = { grant: null, revoke: null };
function report() {
  console.log("\n---- hashes ----");
  console.log(`grant  : ${seen.grant ?? "none seen"}`);
  console.log(`revoke : ${seen.revoke ?? "none seen"}`);
  console.log(`wallet : ${saved.address}`);
  console.log(`explorer: https://explorer.altana.network/address/${saved.address}`);
}

async function withPage(fn) {
  const browser = await chromium.launch();
  const context = await browser.newContext();
  const page = await context.newPage();
  const cdp = await context.newCDPSession(page);
  await cdp.send("WebAuthn.enable");
  const { authenticatorId } = await cdp.send("WebAuthn.addVirtualAuthenticator", {
    options: {
      protocol: "ctap2",
      transport: "internal",
      hasResidentKey: true,
      hasUserVerification: true,
      isUserVerified: true,
      automaticPresenceSimulation: true,
    },
  });
  for (const c of saved.credentials) {
    await cdp.send("WebAuthn.addCredential", { authenticatorId, credential: c });
  }
  try {
    return await fn({ page, context });
  } finally {
    await browser.close();
  }
}

const readSessions = (page) =>
  page.evaluate((k) => JSON.parse(window.localStorage.getItem(k) ?? "[]"), SESSIONS_KEY);

async function prime(page, sessions) {
  await page.goto(`${WEB}/sessions`, { waitUntil: "domcontentloaded", timeout: 60_000 });
  await page.evaluate(
    ([wk, sk, w, s]) => {
      window.localStorage.setItem(wk, JSON.stringify(w));
      window.localStorage.setItem(sk, JSON.stringify(s));
    },
    [WALLET_KEY, SESSIONS_KEY, saved.wallet, sessions],
  );
  await page.reload({ waitUntil: "domcontentloaded", timeout: 60_000 });
  const region = page.getByRole("region", { name: "Sessions" });
  await region.waitFor({ timeout: 30_000 });
  return region;
}

// The page renders the balance it read from chain. Reading it back is the
// cheapest way to confirm the relay and the RPC both answered before we ask
// for anything that costs money.
async function gasBalance(region) {
  const txt = await region.getByText(/BNB\s*$/).first().textContent().catch(() => null);
  return (txt ?? "").trim();
}

async function grant() {
  return withPage(async ({ page }) => {
    const region = await prime(page, saved.sessions ?? []);
    console.log(`gas balance on the wallet: ${await gasBalance(region)}`);

    const before = (await readSessions(page)).length;
    await region.getByLabel("Spend cap").fill(String(CAP));
    await region.getByLabel("Expiry").selectOption(String(EXPIRY)).catch(async () => {
      // The select offers a fixed set. If this expiry is not one of them,
      // leave whatever the page defaults to rather than guessing a value.
      console.log(`expiry ${EXPIRY}s is not one of the offered choices, keeping the default`);
    });

    console.log("granting, this signs and pays a relay fee");
    await region.getByRole("button", { name: "Grant this session" }).click();

    // Wait on the stored record, not on a spinner: the record is written
    // only once the relay has returned a transaction hash.
    let sessions = [];
    try {
      await page.waitForFunction(
        ([k, n]) => JSON.parse(window.localStorage.getItem(k) ?? "[]").length > n,
        [SESSIONS_KEY, before],
        { timeout: 180_000 },
      );
      sessions = await readSessions(page);
    } catch {
      const err = await region.getByRole("alert").textContent().catch(() => null);
      console.error(`\nno session record appeared. page said: ${err ?? "(nothing)"}`);
      console.error("If a fee was taken the grant may still have landed.");
      throw new Error("grant did not complete");
    }

    const s = sessions[0];
    seen.grant = s.grantTx ?? null;
    save(sessions);
    console.log(`granted`);
    console.log(`  session key ${s.publicKey}`);
    console.log(`  cap         ${s.cap} per ${s.period}`);
    console.log(`  expires     ${new Date(s.expiry * 1000).toISOString()}`);
    console.log(`  tx          ${s.grantTx}`);
    return sessions;
  });
}

async function revoke(sessions) {
  return withPage(async ({ page }) => {
    const region = await prime(page, sessions ?? saved.sessions ?? []);
    const live = (await readSessions(page)).filter((s) => !s.revokedAt);
    if (!live.length) {
      console.log("no live session to revoke");
      return sessions;
    }
    console.log(`revoking ${live[0].publicKey}`);
    await region.getByRole("button", { name: "Revoke now" }).first().click();

    try {
      await page.waitForFunction(
        (k) => JSON.parse(window.localStorage.getItem(k) ?? "[]").some((s) => s.revokedTx),
        SESSIONS_KEY,
        { timeout: 180_000 },
      );
    } catch {
      const err = await region.getByRole("alert").textContent().catch(() => null);
      console.error(`\nrevoke not recorded. page said: ${err ?? "(nothing)"}`);
      throw new Error("revoke did not complete");
    }

    const after = await readSessions(page);
    const done = after.find((s) => s.revokedTx);
    seen.revoke = done?.revokedTx ?? null;
    save(after);
    console.log(`revoked`);
    console.log(`  tx ${done.revokedTx}`);
    return after;
  });
}

/// Everything the grant needs, proved without spending anything: the saved
/// credential restores, the page reaches the relay, and the wallet holds gas.
/// Run this before funding, and again after, so a failed grant is never the
/// first time we learn something is wrong.
async function check() {
  return withPage(async ({ page }) => {
    const region = await prime(page, saved.sessions ?? []);
    const stored = await page.evaluate(
      (k) => JSON.parse(window.localStorage.getItem(k) ?? "null"),
      WALLET_KEY,
    );
    const bal = await gasBalance(region);
    const grantable = await region
      .getByRole("button", { name: "Grant this session" })
      .isVisible()
      .catch(() => false);
    const err = await region.getByRole("alert").textContent().catch(() => null);

    console.log(`site            ${WEB}`);
    console.log(`wallet restored ${stored?.address === saved.address}  (${saved.address})`);
    console.log(`gas balance     ${bal || "(not shown)"}`);
    console.log(`grant control   ${grantable ? "present" : "ABSENT"}`);
    console.log(`page error      ${err ?? "none"}`);
    // Match the number, not the ticker. Mainnet renders "BNB" and testnet
    // "tBNB", and keying on the ticker reported a zero balance as ready.
    const amount = Number.parseFloat(bal);
    const funded = Number.isFinite(amount) && amount > 0;
    const ready = stored?.address === saved.address && grantable && funded;
    console.log(`\nready to grant  ${ready}`);
    if (!funded) console.log("(no gas: fund the wallet address above, then re-run check)");
    return ready;
  });
}

if (mode === "check") {
  await check();
  process.exit(0);
}

if (!YES) {
  console.error("This spends real BNB on mainnet. Re-run with --yes.");
  process.exit(1);
}

try {
  let sessions = saved.sessions ?? [];
  if (mode === "grant" || mode === "both") sessions = await grant();
  if (mode === "revoke" || mode === "both") sessions = await revoke(sessions);
  report();
} catch (e) {
  console.error(`\n${e.message}`);
  report();
  console.error("Check the explorer above before running this again.");
  process.exit(1);
}
