// Create an Altana wallet whose passkey we can keep, and prove we can bring
// it back.
//
// The problem this solves is narrow and expensive. An Altana wallet's
// authority is a passkey, and the private half normally never leaves the
// authenticator. Granting a session costs a fee in native BNB, so the wallet
// has to be funded first. Fund a wallet whose passkey lives in a throwaway
// browser profile and whatever is left after the fee is gone for good, along
// with any ability to revoke the session later.
//
// A virtual authenticator can be exported. Chrome DevTools Protocol
// WebAuthn.getCredentials hands back each credential including its private
// key, and WebAuthn.addCredential puts one back into a fresh authenticator.
// Saved next to the wallet record the app keeps in localStorage, that is
// enough to reconstruct the same wallet in a later session.
//
// The saved file IS the wallet. It is written outside the repository and
// .gitignore covers it, and it should be treated exactly like a private key.
//
// Usage, from the repository root, with the web app running:
//   node scripts/altana_wallet.mjs create    make a wallet and save it
//   node scripts/altana_wallet.mjs restore   bring it back and prove it
//
// Environment: WEB (default http://localhost:3000)

import { chromium } from "../web/node_modules/playwright/index.mjs";
import { readFileSync, writeFileSync, existsSync, chmodSync } from "node:fs";

const WEB = process.env.WEB ?? "http://localhost:3000";
const STORE = process.env.ALTANA_WALLET_FILE ?? ".altana-wallet.json";
const WALLET_KEY = "trustlist.altana.wallet";
const SESSIONS_KEY = "trustlist.altana.sessions";

const mode = process.argv[2];
if (!["create", "restore"].includes(mode ?? "")) {
  console.error("usage: node scripts/altana_wallet.mjs create|restore");
  process.exit(2);
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
  try {
    return await fn({ page, cdp, authenticatorId });
  } finally {
    await browser.close();
  }
}

async function create() {
  return withPage(async ({ page, cdp, authenticatorId }) => {
    await page.goto(`${WEB}/sessions`);
    const region = page.getByRole("region", { name: "Sessions" });
    await region.getByRole("button", { name: "Create with a passkey" }).click();

    // The wallet exists once the passkey ceremony and the relay call finish,
    // and the app records it in localStorage at that point. Waiting on the
    // record rather than on a spinner means we never save half a wallet.
    await page.waitForFunction(
      (k) => window.localStorage.getItem(k) !== null,
      WALLET_KEY,
      { timeout: 180_000 },
    );

    const wallet = JSON.parse(
      await page.evaluate((k) => window.localStorage.getItem(k), WALLET_KEY),
    );
    const sessions = await page.evaluate((k) => window.localStorage.getItem(k), SESSIONS_KEY);

    // The half that normally cannot be exported.
    const { credentials } = await cdp.send("WebAuthn.getCredentials", { authenticatorId });
    if (!credentials.length) throw new Error("the authenticator holds no credential to save");

    const payload = {
      warning:
        "This file is the wallet. The credential below is its signing authority. " +
        "Treat it exactly like a private key: never commit it, never paste it anywhere.",
      createdAt: new Date().toISOString(),
      address: wallet.address,
      wallet,
      sessions: sessions ? JSON.parse(sessions) : [],
      credentials,
    };
    writeFileSync(STORE, JSON.stringify(payload, null, 2));
    // Owner read and write only. It is a key.
    chmodSync(STORE, 0o600);

    console.log(`created  ${wallet.address}`);
    console.log(`saved    ${STORE} (mode 600, gitignored)`);
    console.log(`credentials exported: ${credentials.length}`);
    return wallet.address;
  });
}

async function restore() {
  if (!existsSync(STORE)) {
    console.error(`${STORE} does not exist. Run "create" first.`);
    process.exit(1);
  }
  const saved = JSON.parse(readFileSync(STORE, "utf8"));
  return withPage(async ({ page, cdp, authenticatorId }) => {
    for (const c of saved.credentials) {
      await cdp.send("WebAuthn.addCredential", { authenticatorId, credential: c });
    }
    // The app's own record has to come back too: the credential proves who
    // we are, the record says which wallet that maps to.
    await page.goto(`${WEB}/sessions`);
    await page.evaluate(
      ([wk, sk, w, s]) => {
        window.localStorage.setItem(wk, JSON.stringify(w));
        window.localStorage.setItem(sk, JSON.stringify(s));
      },
      [WALLET_KEY, SESSIONS_KEY, saved.wallet, saved.sessions],
    );
    await page.reload();

    const back = JSON.parse(
      await page.evaluate((k) => window.localStorage.getItem(k), WALLET_KEY),
    );
    const { credentials } = await cdp.send("WebAuthn.getCredentials", { authenticatorId });

    const sameAddress = back.address === saved.address;
    const sameCredential =
      credentials.length === saved.credentials.length &&
      credentials.every((c, i) => c.credentialId === saved.credentials[i].credentialId);

    console.log(`restored ${back.address}`);
    console.log(`address matches the saved one : ${sameAddress}`);
    console.log(`credential is the same one    : ${sameCredential}`);
    if (!sameAddress || !sameCredential) {
      console.error("restore did not reproduce the wallet, so do not fund it");
      process.exit(1);
    }
    console.log("this wallet is recoverable, so funding it strands nothing");
    return back.address;
  });
}

await (mode === "create" ? create() : restore());
