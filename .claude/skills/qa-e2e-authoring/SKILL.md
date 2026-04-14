---
name: qa-e2e-authoring
description: Proactive guardrails for writing Playwright E2E tests. Auto-activates when creating or editing spec files, page objects, or test utilities. Enforces 2026 industry best practices and prevents common flakiness causes.
user-invocable: false
---

# E2E Test Authoring Guide

Applies when Claude is creating or modifying any of:

- `**/*.spec.ts` / `**/*.spec.js`
- `**/tests/pages/*.ts` (page objects)
- `**/tests/utils/*.ts` (test utilities)
- `**/e2e/**/*.ts`

The rules below are enforced during authoring, not after. The `/qa-review` skill handles
post-hoc review.

---

## Non-negotiable rules

### 1. Every async Playwright call must be `await`ed

Missing `await` is the single largest cause of E2E flakiness industry-wide. The test races
past the action while it is still in flight.

```ts
// WRONG
page.click('.submit');
expect(page.locator('.toast')).toBeVisible();

// CORRECT
await page.click('.submit');
await expect(page.locator('.toast')).toBeVisible();
```

Applies to: `page.goto`, `locator.*` methods, `expect(locator).*`, `page.waitFor*`,
`page.evaluate`, and anything returning a `Promise`. The `@typescript-eslint/no-floating-promises`
rule catches these mechanically — ensure it is enabled (see the ESLint config in this pack).

### 2. Use web-first, auto-retrying assertions

Snapshot-in-time checks (`const x = await locator.textContent(); expect(x).toBe(...)`) miss
content that arrives a few ms later. Playwright's matchers retry until timeout.

```ts
// WRONG
const text = await locator.textContent();
expect(text).toContain('Success');

const count = await locator.count();
expect(count).toBe(3);

// CORRECT
await expect(locator).toContainText('Success');
await expect(locator).toHaveCount(3);
```

Same for `toHaveValue`, `toHaveURL`, `toBeVisible`, `toBeEnabled`, `toBeChecked`,
`toHaveAttribute`, `toHaveClass`.

### 3. Locator hierarchy — prefer stability

Use locators in this order (most stable first):

1. `getByRole()` / `getByLabel()` / `getByPlaceholder()` — survive markup changes
2. `[data-testid="..."]` — explicit test hook
3. `#id` — stable if the id is meaningful (not a CSS-module hash)
4. `[class*="ComponentName"]` — partial match survives CSS-module hashing
5. Tag + attribute combos (`a[href*="/contact"]`)
6. **Avoid `getByText()` and `text=` selectors** — they break on content changes,
   i18n, and CMS edits

### 4. No hard waits

`page.waitForTimeout(N)` is almost always wrong. It pauses execution for a fixed duration
regardless of whether the app is ready, producing fast-machine races and slow-machine timeouts.

```ts
// WRONG
await page.click('.submit');
await page.waitForTimeout(2000);
await expect(page.locator('.result')).toBeVisible();

// CORRECT — the assertion retries until the element appears
await page.click('.submit');
await expect(page.locator('.result')).toBeVisible();
```

If you absolutely need a delay (rate-limiting between data-driven iterations), add an
`eslint-disable` comment explaining why.

### 5. Never use `waitForLoadState('networkidle')`

Officially discouraged in Playwright's 2026 docs. It hangs on any page with persistent
network activity — analytics beacons, WebSockets, HLS video streams, polling, SSE, CMS
live-preview connections.

```ts
// WRONG — will hang on any page with a video player
await page.goto(url);
await page.waitForLoadState('networkidle');

// CORRECT — wait on what you actually care about
await page.goto(url, { waitUntil: 'domcontentloaded' });
await expect(page.getByRole('main')).toBeVisible();
```

### 6. Descriptive assertion messages

Every `expect()` should include a message that names what is being validated and why it
matters. Without it, CI shows "expected 3 to be 5" with no context.

```ts
// WRONG
expect(count).toBe(expected);

// CORRECT
expect(count, `Product count for ${region} should match catalog`).toBe(expected);
```

Prioritize messages in loops and data-driven tests where the iteration variable must appear
in the failure output.

### 7. Timeouts set explicitly when needed

The global default is 30s — too short for pages with lazy loading, many images, or
multi-step flows. Set `test.setTimeout()` at the top of tests that need more.

```ts
test('heavy page with lazy images', async ({ page }) => {
  test.setTimeout(120_000);
  // ...
});
```

### 8. `test.step()` for readable traces

Group logical phases so the trace viewer reads as a narrative:

```ts
await test.step('Navigate to product page', async () => { ... });
await test.step('Apply filters', async () => { ... });
await test.step('Verify results', async () => { ... });
```

### 9. Soft vs hard assertions

- **Hard** `expect()` — preconditions where continuing is meaningless (page loaded,
  data not null).
- **Soft** `expect.soft()` — independent checks where collecting all failures matters
  (iterating products, multiple field validations, screenshot comparisons).

```ts
// Collect all bad images, don't stop on first
for (const img of images) {
  expect.soft(img.naturalWidth, `${img.src} should have loaded`).toBeGreaterThan(0);
}
```

### 10. No committed debugging artifacts

Never commit `test.only`, `test.describe.only`, `page.pause()`, `debugger`, or
`console.log()` in spec files. A PostToolUse hook in this pack blocks these automatically.

---

## Page Object Model

```ts
import { Page, Locator, expect } from '@playwright/test';

export class CheckoutPage {
  readonly submitButton: Locator;
  readonly errorToast: Locator;

  constructor(readonly page: Page) {
    this.submitButton = page.getByRole('button', { name: 'Submit' });
    this.errorToast = page.locator('[data-testid="error-toast"]');
  }

  async submit() {
    await this.submitButton.click();
  }

  async expectError(message: string | RegExp) {
    await expect(this.errorToast).toContainText(message);
  }
}
```

- Locators are `readonly` properties initialized in the constructor
- Constructor takes `page: Page` (and optionally `isMobile: boolean`)
- Methods are `async`, return typed values, never `any`
- Prefer actions + assertion helpers over exposing raw locators where possible

### Dual desktop/mobile DOM

Many responsive sites render **both** layouts simultaneously and toggle visibility with
CSS. Playwright matches hidden elements too, causing strict-mode violations. Always scope
queries to the visible container:

```ts
// Scope to the container that is actually showing
const desktopNav = page.locator('nav.desktop-nav');
const mobileNav = page.locator('nav.mobile-nav');
const activeNav = (await desktopNav.isVisible()) ? desktopNav : mobileNav;
```

`isMobile` is a Playwright test fixture, not a runtime DOM state. iPads and other tablets
often have `isMobile: false` but render mobile layouts. Prefer runtime visibility checks
when the layout could go either way.

---

## Data-driven tests

Use the `for...of` + `test.describe` pattern, not `test.each`:

```ts
import { test, expect } from '@playwright/test';
import { productUrls } from './data/urls';

for (const { url, title, region } of productUrls) {
  test.describe(title, () => {
    test(`loads cleanly on ${region}`, async ({ page }) => {
      await page.goto(url);
      await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
    });
  });
}
```

- Titles must include the parameterized variable so failures are identifiable from the
  report alone
- Gate region- or variant-specific assertions behind feature flags in the test data
  (e.g. `hasSampleCTA: boolean`), never hardcoded `if (region === 'US')` chains

---

## Visual regression tests (`visual-*.spec.ts`)

Visual diffs are flaky unless you aggressively pin the render. Required before any
screenshot:

### Disable animations and transitions

```ts
await page.addStyleTag({
  content: `
    *, *::before, *::after {
      animation-duration: 0s !important;
      transition-duration: 0s !important;
    }
  `,
});
```

### Hide unpredictable overlays

Cookie banners, Hotjar, Intercom, Drift, etc. — hide whatever your site injects:

```ts
await page.addStyleTag({
  content: `
    #CybotCookiebotDialog,
    ._hj-widget-container,
    .intercom-launcher { display: none !important; }
  `,
});
```

### Pause auto-playing video

```ts
await page.locator('video').evaluateAll((videos: HTMLVideoElement[]) => {
  videos.forEach((v) => { v.pause(); v.currentTime = 0; });
});
```

### Freeze carousels/slideshows

Clear timers and pin transforms:

```ts
await page.evaluate(() => {
  const maxId = window.setTimeout(() => {}, 0);
  for (let i = 0; i <= maxId; i++) {
    window.clearTimeout(i);
    window.clearInterval(i);
  }
});
await page.addStyleTag({
  content: `.carousel-track { transition: none !important; transform: translateX(0) !important; }`,
});
```

### Sort randomized DOM sections

"Related products", "You might also like", etc. reorder on every render. Sort by a stable
attribute before screenshot:

```ts
await page.evaluate(() => {
  document.querySelectorAll('.recommendations').forEach((container) => {
    const cards = Array.from(container.children) as HTMLElement[];
    cards.sort((a, b) => (a.querySelector('a')?.href ?? '').localeCompare(b.querySelector('a')?.href ?? ''));
    cards.forEach((c) => container.appendChild(c));
  });
});
```

### Soft-assert screenshots

Use `expect.soft()` on snapshots so functional checks still run when pixels drift:

```ts
const screenshot = await componentLocator.screenshot();
expect.soft(screenshot).toMatchSnapshot('component.png');
```

### Tune `maxDiffPixels` per test profile

Full-page shots of data-driven pages need looser tolerances than tight component shots.
Configure per test or per `toHaveScreenshot` call:

```ts
await expect(page).toHaveScreenshot({ fullPage: true, maxDiffPixels: 150 });
```

---

## Debugging

Prefer the trace viewer to videos/screenshots. Enable in `playwright.config.ts`:

```ts
export default defineConfig({
  use: { trace: 'on-first-retry' },
});
```

Then after a failure:

```bash
npx playwright show-trace test-results/.../trace.zip
```

Never commit `page.pause()`, `test.only`, or `console.log()` for debugging — use the trace
viewer or `--debug` flag instead.

---

## Running tests

```bash
# Always pass --reporter=line when running via CLI/CI so output is visible
npx playwright test tests/example.spec.ts --reporter=line

# Run only a tagged subset
npx playwright test --grep @regression --reporter=line
```

---

**Skill version:** 1.0 — April 2026
