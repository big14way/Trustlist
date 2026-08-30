import { test, expect } from "@playwright/test";

// SPEC.md Section 30.5 says to walk the dead end table manually before
// submission. The rows that are a matter of layout or of what a page says
// are cheaper to check here than by hand, and unlike a manual walk they stay
// checked. The rows that need a wallet, a stuck transaction or a dead RPC
// stay manual and are recorded in docs/DEAD_ENDS.md.

const PAGES = ["/", "/jobs", "/stats", "/methodology", "/sessions"];

test.describe("no horizontal scroll at 360px", () => {
  for (const path of PAGES) {
    test(`${path} fits a 360px viewport`, async ({ page }) => {
      await page.setViewportSize({ width: 360, height: 720 });
      await page.goto(path);
      await page.waitForLoadState("networkidle");
      const overflow = await page.evaluate(() => {
        const doc = document.documentElement;
        return doc.scrollWidth - doc.clientWidth;
      });
      // A pixel of rounding is not a horizontal scrollbar.
      expect(overflow, `${path} overflows by ${overflow}px`).toBeLessThanOrEqual(1);
    });
  }
});

test("a missing page explains itself and offers a way out", async ({ page }) => {
  const res = await page.goto("/nosuchpage");
  expect(res?.status()).toBe(404);
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  // A dead end is a page with no exit. There must be a link home.
  await expect(page.getByRole("link", { name: /marketplace|home/i }).first()).toBeVisible();
});

test("an agent that does not exist explains itself", async ({ page }) => {
  const res = await page.goto("/agents/999999999");
  expect(res?.status()).toBe(404);
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  await expect(page.getByRole("link", { name: /marketplace|home/i }).first()).toBeVisible();
});

test("an empty result set offers something to click", async ({ page }) => {
  // A category with nothing answering is the ordinary way to reach the empty
  // state. Section 18.5 requires an action, not just an apology.
  await page.goto("/?category=grid-trading");
  const cards = page.locator("section[aria-label='Agents'] li");
  if ((await cards.count()) === 0) {
    const region = page.getByTestId("empty-state");
    await expect(region).toBeVisible();
    await expect(region.getByRole("link").first()).toBeVisible();
  }
});

test("status is never carried by colour alone", async ({ page }) => {
  await page.goto("/");
  await page.waitForLoadState("networkidle");
  const pills = page.locator("[data-status-pill]");
  const n = await pills.count();
  expect(n).toBeGreaterThan(0);
  for (let i = 0; i < n; i++) {
    const text = (await pills.nth(i).innerText()).trim();
    expect(text.length, "every status pill carries a word").toBeGreaterThan(0);
  }
});

test("the probe strip reads as a sentence", async ({ page }) => {
  await page.goto("/");
  await page.waitForLoadState("networkidle");
  const strip = page.getByRole("img").first();
  const label = await strip.getAttribute("aria-label");
  expect(label).toMatch(/answered|no probes recorded/);
});
