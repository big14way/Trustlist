import { expect, test } from "@playwright/test";

// Golden journey 05: somebody arrives with no wallet extension, no funds,
// and no idea what ERC-8004 is. Everything that does not need a wallet must
// work, and the one thing that does need a wallet must say so plainly
// instead of failing at signing time or showing a dead button.
//
// No wallet is injected in this file on purpose. That is the whole point.

const API = process.env.API ?? "http://localhost:8080";

test.beforeEach(async ({ page }) => {
  page.on("pageerror", (e) => {
    throw new Error(`a cold visitor hit a page error: ${e.message}`);
  });
});

test("no wallet, no funds, and the product is still fully readable", async ({
  page,
}) => {
  await page.goto("/");

  // The claim is on the page and it is our own measurement, not a slogan.
  await expect(page.getByRole("heading", { level: 1 })).toContainText(
    "Most agents are not there",
  );

  const cards = page.locator("main section[aria-label='Agents'] li");
  await expect(cards.first()).toBeVisible();
  expect(await cards.count()).toBeGreaterThan(0);

  // Hire is offered, and without a wallet it explains itself rather than
  // throwing. A dead end here is the most expensive failure in the product.
  await cards.first().getByRole("button", { name: "Hire" }).click();
  const sheet = page.getByRole("dialog");
  await expect(sheet).toBeVisible();
  await expect(
    sheet.getByText(/wallet/i).first(),
    "the sheet must name the missing wallet",
  ).toBeVisible();
  await page.keyboard.press("Escape");

  // An agent page reads end to end with no wallet.
  const firstLink = cards.first().getByRole("link").first();
  await firstLink.click();
  await expect(page).toHaveURL(/\/agents\//);
  await expect(page.getByRole("region", { name: "Scores" })).toBeVisible();
  await expect(page.getByRole("region", { name: "Reviews" })).toBeVisible();

  // The methodology is reachable and says what the numbers mean, because the
  // whole thesis is one number and it has to survive first contact.
  await page.goto("/methodology");
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  await expect(page.getByText(/prior/i).first()).toBeVisible();

  // And the page agrees with the API that serves the engine's own constants,
  // so a reader is not shown a prettied up version of the real rules.
  const method = await (await fetch(`${API}/v1/methodology`)).json();
  await expect(
    page.getByText(String(method.reputation.prior_strength)).first(),
  ).toBeVisible();

  // Stats and jobs render for a stranger too.
  await page.goto("/stats");
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  await page.goto("/jobs");
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
});
