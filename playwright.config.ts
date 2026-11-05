// Changing this file needs the maintainer's explicit approval (AGENTS.md).

import { defineConfig } from "@playwright/test";

// The browser checks run against a `phyllon serve` that is already up. CI
// starts it, and so does the developer. Fail at once when nobody said where it
// is, instead of testing a default address that may be someone else's server.
const baseURL = process.env.PHYLLON_BASE_URL;
if (!baseURL) {
  throw new Error(
    "PHYLLON_BASE_URL is not set. Start `phyllon serve` and set it to the " +
      "server's address, for example http://127.0.0.1:8080",
  );
}

export default defineConfig({
  testDir: "tests/browser",
  // Screenshots and failure traces land here, which .gitignore covers and CI
  // uploads.
  outputDir: "test-results",
  // The list reporter only prints. The HTML reporter would serve its report
  // and open a browser when a test fails.
  reporter: "list",
  forbidOnly: !!process.env.CI,
  retries: 0,
  use: {
    baseURL,
    trace: "retain-on-failure",
  },
  projects: [{ name: "chromium", use: { browserName: "chromium" } }],
});
