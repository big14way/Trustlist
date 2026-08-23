import { expect, test } from "@playwright/test";
import { agentDelivers, tokenBalance } from "../chain";
import { injectedWalletScript } from "../injectedWallet";

// Golden journey 01: a stranger lands on the marketplace, picks an agent
// that is actually answering, hires it, the agent delivers, and the hirer
// releases the escrow. Nothing is simulated except the wallet extension:
// the app, the API, the HireRail contract, and the chain are all real.

const RPC = process.env.DEV_RPC ?? "http://localhost:8545";
const API = process.env.API ?? "http://localhost:8080";
const ACCOUNT = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";

type Job = {
  job_id: string;
  provider: string;
  state: string;
  budget: string;
  mode: string;
};

async function listJobs(): Promise<Job[]> {
  const res = await fetch(`${API}/v1/jobs?hirer=${ACCOUNT}`);
  const body = (await res.json()) as { items: Job[] };
  return body.items;
}

function highestJobId(jobs: Job[]): bigint {
  return jobs.reduce((max, j) => (BigInt(j.job_id) > max ? BigInt(j.job_id) : max), 0n);
}

test.beforeEach(async ({ page }) => {
  await page.addInitScript(injectedWalletScript(RPC, ACCOUNT));
  page.on("pageerror", (e) => console.log(`  [pageerror] ${e.message}`));
});

test("discover an answering agent, hire it, and release the escrow", async ({
  page,
}) => {
  const kernel = process.env.DEV_KERNEL;
  const token = process.env.DEV_TOKEN;
  if (!kernel || !token) {
    throw new Error("DEV_KERNEL and DEV_TOKEN must be set for this suite");
  }

  // Anchor on what already exists so this run acts only on its own job.
  const jobsBefore = highestJobId(await listJobs());

  const started = Date.now();
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toContainText(
    "Most agents are not there",
  );

  // The marketplace leads with agents that answered when we probed.
  const firstCard = page.locator("main section[aria-label='Agents'] li").first();
  await expect(firstCard).toBeVisible();
  await expect(firstCard.getByText(/live|flaky/i).first()).toBeVisible();

  // Hire is on the card itself, not buried on a detail page.
  await firstCard.getByRole("button", { name: "Hire" }).click();

  const sheet = page.getByRole("dialog");
  await expect(sheet).toBeVisible();

  // The settlement choice is stated before any money moves.
  await expect(sheet.getByText("You release it")).toBeVisible();
  await expect(sheet.getByText("Nobody releases it alone")).toBeVisible();

  await sheet.getByRole("button", { name: /Connect wallet/i }).click();

  await sheet.locator("input").first().fill("2");
  const confirm = sheet.getByRole("button", { name: /Hire for|Approve and hire/i });
  await expect(confirm).toBeEnabled();
  await confirm.click();

  await expect(sheet.getByText("Hired.")).toBeVisible({ timeout: 60_000 });
  const hireSeconds = (Date.now() - started) / 1000;
  console.log(`journey 01 discover to hired: ${hireSeconds.toFixed(1)}s`);
  await sheet.getByRole("button", { name: "Done" }).click();

  // Wait for our specific job to reach the indexer, not merely any job.
  let mine: Job | undefined;
  await expect(async () => {
    const jobs = await listJobs();
    mine = jobs.find((j) => BigInt(j.job_id) > jobsBefore);
    expect(mine, "the new hire reached the indexer").toBeTruthy();
  }).toPass({ timeout: 60_000 });
  const job = mine as Job;
  expect(job.mode).toBe("direct");
  expect(job.budget).toBe("2000000000000000000");

  // The agent delivers.
  const before = await tokenBalance(token, job.provider);
  await agentDelivers(kernel, job.provider, job.job_id);

  // The decision appears on that job's own panel once the work is in.
  await page.goto("/jobs");
  const panel = page
    .locator("main ul li")
    .filter({ hasText: `JOB ${job.job_id} ` });
  await expect(async () => {
    await page.reload();
    await expect(panel.getByRole("button", { name: /Accept and pay/i })).toBeVisible({
      timeout: 5_000,
    });
  }).toPass({ timeout: 60_000 });

  await panel.getByRole("button", { name: /Accept and pay/i }).click();

  // The agent receives the exact budget, released by the hirer alone.
  await expect(async () => {
    const after = await tokenBalance(token, job.provider);
    expect(after - before).toBe(BigInt(job.budget));
  }).toPass({ timeout: 60_000 });

  // And the job reads as completed everywhere, not just in the wallet.
  await expect(async () => {
    const jobs = await listJobs();
    const settled = jobs.find((j) => j.job_id === job.job_id);
    expect(settled?.state).toBe("completed");
  }).toPass({ timeout: 60_000 });

  const total = (Date.now() - started) / 1000;
  console.log(
    `journey 01 complete in ${total.toFixed(1)}s: job ${job.job_id}, ${job.budget} released to the agent`,
  );
});
