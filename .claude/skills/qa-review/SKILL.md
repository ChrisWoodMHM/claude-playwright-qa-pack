---
name: qa-review
description: Reviews Playwright E2E test code against the QA Pack checklist. Invoked with /qa-review [path], or with no arguments to review all modified files.
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash
argument-hint: [file-or-directory]
---

# QA Review

Review the code specified by `$ARGUMENTS`. If none is given, run
`git diff --name-only && git diff --cached --name-only` and review every modified `.ts` /
`.js` file under test directories (`e2e/`, `tests/`, `spec/`, `playwright/`).

Read every file in full before making observations. Do not guess from filenames.

---

## Review categories

Apply only the categories relevant to each file. Do not force irrelevant checks.

### All files

**Missing `await`** — Every call to an async Playwright API (`page.goto`, `locator.*`,
`expect(locator).*`, `page.waitFor*`, `page.evaluate`) must be `await`ed. Missing awaits are
the #1 cause of flakiness — the test races past the action. Also check inside `evaluate()`
callbacks and event handlers.

**Assertion messages** — Every `expect()` and `expect.soft()` should include a descriptive
custom message. Without it, CI shows "expected 3 to be 5" with no context. Prioritize
assertions inside loops and data-driven tests.

**Silent error swallowing** — Flag empty `.catch(() => {})` blocks and `catch (e) { continue }`
patterns. Each must have a comment explaining why it is safe to ignore.

**Hardcoded secrets** — No API keys, tokens, passwords, or credentials in source. Must come
from env vars. Flag `Bearer ...`, `sk-...`, `pk-...`, long base64, and variables named
`token`, `secret`, `apiKey`, `password` assigned to string literals.

**Debug artifacts** — Flag any `page.pause()`, `debugger` statement, `console.log()`,
`test.only()`, or `test.describe.only()` left in committed code.

**Deprecated APIs** — Flag usage that breaks on future Playwright upgrades:
- `page.waitForSelector()` → `locator.waitFor()` or `expect(locator).toBeVisible()`
- `page.$()` / `page.$$()` → `page.locator()`
- `page.$eval()` / `page.$$eval()` → `locator.evaluate()` / `locator.evaluateAll()`
- `elementHandle` methods → Locator API
- `page.waitForNavigation()` → `page.waitForURL()` or `expect(page).toHaveURL()`

**Web-first assertions** — Flag snapshot-in-time patterns:
- `const text = await locator.textContent(); expect(text).toContain(...)` → `toContainText()`
- `const count = await locator.count(); expect(count).toBe(N)` → `toHaveCount(N)`
- `const val = await input.inputValue(); expect(val).toBe(...)` → `toHaveValue(...)`
- `if (await locator.count() > 0)` for existence checks → `locator.waitFor({ state: 'attached' })`

**Test isolation** — Tests within `test.describe` must be independent by default. Flag
mutable `let` variables at describe scope written by one test and read by another. If
interdependency is intentional, the describe must use
`test.describe.configure({ mode: 'serial' })` and the shared state should be commented.

### Spec files (`*.spec.ts` / `*.spec.js`)

**Wait strategy** — Flag `page.waitForLoadState('networkidle')` (hangs on pages with
persistent connections — WebSockets, analytics, HLS video). Flag `page.waitForTimeout(N)`
(hard wait). Suggest a condition-based wait: `waitFor`, `expect().toBeVisible()`,
`waitForURL`, `toPass`.

**Timeouts** — Tests with lazy loading, form submission, or multi-step flows should set
`test.setTimeout()` explicitly. The 30s global default is usually too short.

**Test structure** — Prefer `test.step()` blocks for logical phases. Data-driven tests
should use `for...of` + `test.describe` + `test()`, not `test.each`.

**Test meaningfulness** — Flag tests that:
- Assert trivially true conditions (`expect(true).toBe(true)`, `expect(arr.length).toBeGreaterThanOrEqual(0)`)
- Have assertions that don't validate the behavior described in the title
- Only assert that the page loaded — a navigation-only test is not meaningful
- Use weak inequality (`afterTransform !== initialTransform`) — passes even if the value
  changed in the wrong direction
- Contain `if` guards that can cause zero assertions to execute — every code path must
  execute at least one assertion
- Re-verify prop-driven behavior at multiple viewports when the behavior isn't viewport-
  dependent (adds no coverage)
- Provide no unique coverage beyond what other tests in the suite already assert

**Test naming** — Titles should describe expected behavior, not just the action.
`'Checkout blocks submission when email is invalid'` beats `'Test checkout'`. Data-driven
titles must include the parameterized variable.

**Network resilience** — Use `page.goto(url, { waitUntil: 'domcontentloaded' })` on pages
with heavy third-party scripts. Pages served by ISR may return stale or 404 content on first
visit — document via `test.info().annotations` rather than silently passing/failing.

**Visual tests** — Sections with randomized content must be hidden, masked, or DOM-sorted
before screenshot. Fade-in transitions must be disabled via CSS injection. Third-party
overlays (cookie banners, Hotjar, Intercom) must be hidden.

**Mobile/desktop** — `isMobile` is a Playwright fixture, not a runtime DOM check. Tablets
often have `isMobile: false` but render mobile layouts. Prefer runtime visibility checks
when the rendered layout could go either way.

### Page objects (`pages/*.ts`, `*-page.ts`)

**Structure** — Locators are `readonly` properties initialized in the constructor.
Constructor takes `page: Page` (optionally `isMobile: boolean`). Methods are `async` with
typed returns — never `any`.

**Locator hierarchy** — Prefer, in order:
1. `getByRole()` / `getByLabel()` / `getByPlaceholder()` — semantic, resilient
2. `[data-testid="..."]` — explicit test hook
3. `#id` — if meaningful (not CSS-module hash)
4. `[class*="ComponentName"]` — partial match survives hashing
5. Tag + attribute (`a[href*="/contact"]`)
6. **Avoid** `getByText()` and `text=` — breaks on content changes, i18n, CMS edits

Flag fragile selectors that depend on exact generated class names, child index without
semantic meaning, or DOM structure likely to change. When multiple containers can match,
use `.first()`, `.nth()`, or a more specific parent scope.

**Dead code** — Flag methods defined but never called from any spec file. Verify with Grep.

### Utilities (`utils/*.ts`, `helpers/*.ts`)

**Type safety** — No implicit `any` on parameters or returns. Use `as EventListener` for
typed DOM event callbacks.

**Shared vs inline** — If a pattern appears in 3+ spec files, extract to utils. Flag
utility functions only used once (unnecessary abstraction).

---

## Output format

```
## Review: <filename>

### Issues

**[CRITICAL]** <description>
- File: <path>:<line>
- Why: <explanation of the bug or reliability risk>
- Fix: <specific code change>

**[WARNING]** <description>
- File: <path>:<line>
- Why: <explanation>
- Fix: <suggestion>

**[STYLE]** <description>
- File: <path>:<line>
- Fix: <suggestion>

### Passed checks
- <brief list of categories that look correct>
```

**Severity:**
- **CRITICAL** — will cause test failures, flakiness, or incorrect results. Must fix.
- **WARNING** — could cause issues in edge cases or reduces maintainability. Should fix.
- **STYLE** — convention mismatch or minor improvement. Nice to fix.

If a file has no issues, say so briefly and move on. Do not pad with praise.

After reviewing all files, provide a summary: `X critical, Y warnings, Z style issues
across N files`. Then ask the user whether to apply fixes.
