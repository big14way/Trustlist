import { expect, test } from "@playwright/test";
import { advanceChain, chainTime, tokenBalance } from "../chain";
import { injectedWalletScript } from "../injectedWallet";

// Golden journey 04: the agent takes the job and never delivers. The hirer
// should not need to ask anyone for help, wait for support, or understand
// the ERC-8183 state machine. The deadline passes, a reclaim button appears
// on its own, and the money comes back.
//
// Nothing here is simulated except the wallet extension and the passage of
// time, which is advanced on the chain and in the browser together.

const RPC = process.env.DEV_RPC ?? "http://localhost:8545";
const API = process.env.API ?? "http://localhost:8080";
const ACCOUNT = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
const ONE_HOUR = 3600;

type Job = {
  job_id: string;
  hirer: string;
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
  return jobs.reduce(
    (max, j) => (BigInt(j.job_id) > max ? BigInt(j.job_id) : max),
    0n,
  );
}

test("an agent that never delivers, and the hirer takes the escrow back", async ({
  page,
}) => {
  const token = process.env.DEV_TOKEN;
  if (!token) throw new Error("DEV_TOKEN must be set for this suite");

  // The browser clock has to move with the chain, so it is installed before
  // anything renders.
  await page.clock.install();
  await page.addInitScript(injectedWalletScript(RPC, ACCOUNT));

  const jobsBefore = highestJobId(await listJobs());
  const balanceBefore = await tokenBalance(token, ACCOUNT);

  await page.goto("/");
  const firstCard = page.locator("main section[aria-label='Agents'] li").first();
  await expect(firstCard).toBeVisible();
  await firstCard.getByRole("button", { name: "Hire" }).click();

  const sheet = page.getByRole("dialog");
  await sheet.getByRole("button", { name: /Connect wallet/i }).click();
  await sheet.locator("input").first().fill("2");

  // The shortest deadline the product offers, so the wait is an hour rather
  // than a week.
  await sheet.getByRole("button", { name: "1 hour" }).click();

  const confirm = sheet.getByRole("button", {
    name: /Hire for|Approve and hire/i,
  });
  await expect(confirm).toBeEnabled();
  await confirm.click();
  await expect(sheet.getByText("Hired.")).toBeVisible({ timeout: 60_000 });
  await sheet.getByRole("button", { name: "Done" }).click();

  let mine: Job | undefined;
  await expect(async () => {
    const jobs = await listJobs();
    mine = jobs.find((j) => BigInt(j.job_id) > jobsBefore);
    expect(mine, "the new hire reached the indexer").toBeTruthy();
  }).toPass({ timeout: 60_000 });
  const job = mine as Job;
  expect(job.state).toBe("funded");

  // Before the deadline there is nothing to reclaim, and the panel should not
  // offer it.
  await page.goto("/jobs");
  const panel = page.locator("main ul li").filter({ hasText: `JOB ${job.job_id} ` });
  await expect(panel).toBeVisible();
  await expect(
    panel.getByRole("button", { name: /Reclaim/i }),
  ).toHaveCount(0);

  // The agent does nothing at all. Time passes.
  const before = await chainTime();
  await advanceChain(ONE_HOUR + 600);
  expect(await chainTime()).toBeGreaterThan(before + ONE_HOUR);
  await page.clock.fastForward((ONE_HOUR + 600) * 1000);

  // The button appears without anyone being told it exists.
  await page.reload();
  const reclaim = panel.getByRole("button", { name: /Reclaim my escrow/i });
  await expect(reclaim).toBeVisible({ timeout: 30_000 });
  await reclaim.click();

  // The money is back, and the job says so rather than leaving the hirer to
  // work it out from a hash.
  await expect(async () => {
    const balance = await tokenBalance(token, ACCOUNT);
    expect(balance).toBe(balanceBefore);
  }).toPass({ timeout: 60_000 });

  await expect(async () => {
    const jobs = await listJobs();
    const now = jobs.find((j) => j.job_id === job.job_id);
    expect(now?.state).toBe("expired");
  }).toPass({ timeout: 60_000 });

  console.log(`journey 04: job ${job.job_id} expired and reclaimed in full`);
});
