import { defineConfig } from "@playwright/test";

// The end to end suite drives a real browser against the real app, the real
// API, and a local chain running the real HireRail contract.
export default defineConfig({
  testDir: "./e2e",
  timeout: 120_000,
  expect: { timeout: 20_000 },
  fullyParallel: false,
  workers: 1,
  reporter: [["list"]],
  use: {
    baseURL: process.env.WEB ?? "http://localhost:3000",
    trace: "retain-on-failure",
  },
});
