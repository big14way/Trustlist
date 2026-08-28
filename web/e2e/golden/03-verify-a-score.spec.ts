import { expect, test } from "@playwright/test";

// Golden journey 03: a reader does not take our word for a score. They open
// an agent, open the verify drawer, and their own browser asks the contract
// whether those numbers are in the published Merkle root. The same proof is
// then replayed with an inflated trust score, which the contract must
// reject. Nothing is stubbed: the root on chain was published from the
// snapshot the trust engine built.

const API = process.env.API ?? "http://localhost:8080";

test("a reader can check a published score against the chain", async ({
  page,
}) => {
  // Pick an agent that is actually in the published snapshot, so the journey
  // never depends on a hardcoded id.
  const latest = await (await fetch(`${API}/v1/snapshots/published`)).json();
  expect(latest.merkle_root).toMatch(/^0x[0-9a-f]{64}$/);
  expect(latest.onchain_index).not.toBeNull();

  const payload = await (
    await fetch(`${API}/v1/snapshots/published?payload=true`)
  ).json();
  const agentId = payload.payload.leaves[0].agent_id as string;

  await page.goto(`/agents/${agentId}`);
  const drawer = page.getByRole("region", { name: "Verify" });
  await drawer.getByRole("button", { name: "check this score" }).click();

  // The root we serve and the root the contract holds must be the same, and
  // the contract must confirm this agent's numbers.
  await expect(drawer.getByText("(same)")).toBeVisible({ timeout: 20_000 });
  await expect(
    drawer.getByText("these numbers are in the published snapshot"),
  ).toBeVisible();

  // And the same proof with a perfect trust score must fail.
  await expect(drawer.getByText("rejected, as it should be")).toBeVisible();
});
