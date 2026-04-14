# Using the QA Pack

How to get the most out of this pack once it's installed. Applies to both humans writing
tests and AI agents (Claude Code, Cursor, etc.) invoked against the test suite.

For *what* to put in a test (assertions, locators, page objects), read the skill files
themselves — they're the canonical reference and auto-apply to AI agents anyway.

---

## The three artifacts, in practice

### `qa-e2e-authoring` — fires automatically

Activates whenever you (or Claude) edit a `*.spec.ts`, a page object, or a test utility.
You don't invoke it. You don't configure it. Edit a test file and the rules apply.

If you're writing tests **without** an AI agent, read the skill file once as a checklist —
it's the same rules, just as a reference rather than enforced.

### `qa-review` — you invoke it

Run `/qa-review` when you want a structured review against the full checklist. Good times:

- **Before committing** a batch of new or changed specs
- **Before asking a human** to review your PR — lets you fix the obvious stuff first
- **After a flaky run** to check whether the test itself has smells

With no argument it reviews all git-modified files. Pass a path to scope it:
`/qa-review e2e/tests/checkout.spec.ts`.

It returns CRITICAL / WARNING / STYLE findings and then asks whether to apply fixes. Say
yes only if you've read the findings — never blindly accept.

### `block-debug-artifacts.sh` — fires on every write

Whenever Claude writes or edits a spec file, this hook greps the result for:

- `test.only()` / `test.describe.only()`
- `page.pause()`
- `debugger` statements
- Likely-secret patterns (Bearer tokens, `sk-...`, credential-shaped string literals)

If any match, the write is blocked with a readable message. Claude will automatically
revise.

**When it fires on you legitimately:** you *actually* need `test.only` for a local debug
run. Acceptable pattern: edit locally, run the test, remove before committing. The hook
only fires on Claude's writes, not on your manual edits — so this is rarely a real
friction point.

---

## Writing a test — the loop

1. **Decide what you're testing and at what layer.** E2E tests are expensive. Prefer API
   or unit tests if the scenario doesn't require full-stack rendering or user interaction.
2. **Find a similar existing test.** Copy its structure. Most spec files in a mature suite
   follow the same template — data-driven for-loop, `test.step()` blocks, page object.
3. **Write with Claude.** The skill auto-activates. Accept its suggestions unless you know
   something it doesn't.
4. **Run it locally.** See the "Running tests" section below.
5. **`/qa-review` the file.** Fix what comes back.
6. **Commit.** The hook catches any debug artifacts you or Claude left behind.

---

## Running tests

```bash
# Clean run, output to terminal
npx playwright test tests/checkout.spec.ts --reporter=line

# With a visible browser — good for watching what's actually happening
npx playwright test tests/checkout.spec.ts --headed --reporter=line

# Interactive UI mode — best for developing new tests
npx playwright test --ui

# Drop into the Playwright Inspector at the first step
npx playwright test tests/checkout.spec.ts --debug

# After a failure, view the full trace (DOM snapshots, network, console)
npx playwright show-trace test-results/<test-name>/trace.zip
```

Enable traces once in `playwright.config.ts` so they're always available:

```ts
use: { trace: 'on-first-retry' }
```

---

## When a test fails — triage

A failed test is one of three things. Figure out which before acting:

### 1. Real regression — the app broke

- The same test fails deterministically on multiple runs
- The trace shows the app behaving differently than expected
- You can reproduce manually in a browser

**Action:** open a bug report with the trace zip + repro steps. Leave the test failing
until the app is fixed. **Do not modify the test to make it pass** — that hides the bug.

### 2. Test bug — the test was wrong

- The test was asserting against an outdated expectation (content changed, design
  refactored, API response shape evolved)
- A locator broke because a role/label/testid legitimately changed

**Action:** update the test. In the PR description, call out what changed and why so
reviewers can verify it's a real app change and not the tester covering up a regression.

### 3. Flake — the test is non-deterministic

- Fails intermittently with no code change
- Passes on retry
- Trace shows a race condition, animation mid-flight, or a missing wait

**Action:** find the root cause. Do **not** add `waitForTimeout()` or retries as a
"fix" — those hide the bug. Typical root causes: missing `await`, `networkidle` on a
page with persistent connections, visible animations/transitions not disabled in visual
tests, shared state between tests in a describe block. The `/qa-review` checklist covers
most of these.

If the flake is caused by a real app race condition (not a test-code issue), treat it as
category 1 — open a bug report.

**Never mask flakes with `test.fail()` or by removing the assertion.** A flaky test is
giving you information; suppress it and you lose the signal.

---

## PR checklist for test changes

Include in your PR description:

- **What** changed and why (new feature coverage, bug repro, refactor)
- **Trace** link or screenshot if the test demonstrates a bug
- **`@regression` tag** if applicable — focused, bounded, deterministic tests qualify;
  large data sweeps and volatile-data tests do not
- **Any locator or data-testid changes** you made to the application to support the test
  (often these belong in a separate app-side PR)

Before requesting review:

- [ ] `/qa-review` returned no CRITICAL findings
- [ ] Test passes locally at least twice in a row (flake check)
- [ ] No `test.only`, `page.pause()`, `debugger`, or `console.log` left in
- [ ] Visual tests: animations disabled, overlays hidden, dynamic content masked/sorted
- [ ] Assertion messages are descriptive — failures will be readable in CI

---

## For AI agents reading this file

- The `qa-e2e-authoring` skill is your default rulebook — follow it without being told.
- Run `/qa-review` after finishing a batch of test edits, before reporting the task as
  complete. Surface findings to the user; don't silently "fix" CRITICAL items without
  their approval if the fix changes test behavior.
- When a test fails: triage first (bug / test-bug / flake) and report your reasoning. Do
  not modify a test to make it pass without confirming the category and asking the user.
- Never add `waitForTimeout`, `test.fail()`, or retries to mask an issue. Follow the rules
  in the skill file.
