import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

// The shell has to hold in both color schemes, because the palette switches
// with prefers-color-scheme.
const schemes = ["light", "dark"] as const;

// Runs axe-core over the page as it stands and fails on any violation. The
// failure message lists each rule with the elements it hit, so the CI log
// says what to fix without opening the report.
async function expectNoViolations(page: Page): Promise<void> {
  const { violations } = await new AxeBuilder({ page }).analyze();
  const report = violations
    .map(
      (violation) =>
        `${violation.id} (${violation.impact ?? "unknown impact"}): ` +
        `${violation.help}\n` +
        violation.nodes.map((node) => `  ${node.target.join(" ")}`).join("\n"),
    )
    .join("\n");
  expect(violations, report).toEqual([]);
}

for (const colorScheme of schemes) {
  test.describe(`${colorScheme} scheme`, () => {
    // Every request of every test is recorded, so a page or an axe run that
    // reaches another origin fails whichever test it happens in.
    let urls: string[] = [];

    test.beforeEach(async ({ page }) => {
      urls = [];
      page.on("request", (request) => urls.push(request.url()));
      await page.emulateMedia({ colorScheme });
    });

    test.afterEach(async ({ baseURL }) => {
      const origin = new URL(baseURL ?? "").origin;
      const foreign = urls.filter((url) => new URL(url).origin !== origin);
      expect(foreign, `requests outside ${origin}`).toEqual([]);
    });

    test("start page has no accessibility violations", async ({ page }) => {
      await page.goto("/");
      await expectNoViolations(page);
    });

    // The server answers 404 here, so the response is not asserted to be ok.
    test("not found page has no accessibility violations", async ({ page }) => {
      const response = await page.goto("/no-such-page");
      expect(response?.status()).toBe(404);
      await expectNoViolations(page);
    });

    // The check itself runs after each test; this one makes sure the start
    // page's own requests reach the list, or an empty list would pass.
    test("no request leaves the origin", async ({ page }) => {
      await page.goto("/", { waitUntil: "networkidle" });
      expect(urls.length).toBeGreaterThan(0);
    });

    test("screenshot of the start page", async ({ page }) => {
      await page.goto("/", { waitUntil: "networkidle" });
      await page.screenshot({
        path: `test-results/shell-${colorScheme}.png`,
        fullPage: true,
      });
    });
  });
}
