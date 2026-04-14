# Writing Testable Code — A QA Primer for Developers

This guide is for the engineers who build the app, not the ones who write the tests.
Every decision you make about HTML, class names, and interactive elements either makes
tests resilient or makes them fragile. Read this once and keep it in mind.

## The short version

1. Use **semantic HTML** so tests can find elements by role, not by brittle CSS.
2. Add **`data-testid`** to any element that isn't inherently addressable — especially
   stateful UI, toast notifications, modals, and dynamic lists.
3. Don't silently rename **user-facing strings** — they are often used as locators.
4. Don't collapse distinct interactive elements into **generic `<div>`s with onClick**.
5. Preserve **stable class-name fragments** when refactoring CSS — tests may target them.
6. When you change visible DOM structure, **tell your QA contact** or leave a PR note.

---

## 1. Prefer semantic HTML

Tests use Playwright's `getByRole()` — this is the **most stable, most accessible** way to
locate elements. It works if and only if your markup uses the right element for the job.

```tsx
// GOOD — addressable by role
<button onClick={submit}>Submit</button>
<nav aria-label="Primary"><a href="/home">Home</a></nav>

// BAD — invisible to role-based locators
<div className="submit-btn" onClick={submit}>Submit</div>
<div className="nav-container"><span onClick={...}>Home</span></div>
```

If a test was targeting `getByRole('button', { name: 'Submit' })` and you replace the
`<button>` with a styled `<div>`, the test breaks silently on the next run.

### Icon-only buttons need accessible names

```tsx
// GOOD — has an accessible name
<button aria-label="Close dialog" onClick={close}><CloseIcon /></button>

// BAD — no text, no aria-label, no role label — tests can't find it
<button onClick={close}><CloseIcon /></button>
```

## 2. Use `data-testid` for non-semantic elements

Some elements don't have a semantic role — status badges, toast containers, specific card
variants. Give them an explicit test hook:

```tsx
<div data-testid="error-toast">{message}</div>
<div data-testid="product-card" data-sku={product.sku}>…</div>
<span data-testid="cart-item-count">{count}</span>
```

Rules:
- Use kebab-case (`data-testid="submit-form"`), not camelCase
- Don't change existing `data-testid` values without coordinating — they are test locators
- Don't add `data-testid` to every element; use it where semantic locators don't work

## 3. User-facing strings are often locators

Tests locate elements by their visible text: button labels, headings, link text, alt
attributes. Renaming "Submit" to "Confirm" **is a breaking change** to the test suite,
even though the behavior is identical.

**When you change user-facing copy:**
- Search the test suite for the old string (`grep -r "Submit" tests/`)
- If matches exist, coordinate with QA or update the tests in the same PR
- For i18n, the test suite uses regexes or locale-aware selectors — see your QA contact

## 4. Don't invent generic interactive elements

If a thing is a button, use `<button>`. If it navigates, use `<a href>`. If it toggles,
use `<button aria-pressed>` or a native checkbox. Custom `<div onClick>` handlers:

- Break keyboard accessibility
- Break screen readers
- Break `getByRole()` locators
- Force tests into fragile CSS-based selectors

If you need custom styling, style the native element. `<button>` is not required to look
like a button.

## 5. Preserve stable class fragments

Modern CSS frameworks hash class names (`.Button_submit_a3f9b`). Tests often cope by
matching a partial fragment (`[class*="Button_submit"]`). When you:

- Rename the CSS module file (`Button.module.css` → `SubmitButton.module.css`)
- Refactor a class name (`submit` → `action-primary`)

...the fragment changes and tests break. If you must rename, either:
- Coordinate with QA so tests update in the same PR, or
- Add a `data-testid` before the rename, let tests migrate, then remove the old class

## 6. DOM restructures deserve a PR note

Moving a component into a different wrapper, re-parenting an element, or splitting one
component into two often changes selector ancestry. A test targeting
`main > .product-grid > article` fails when a new wrapper appears in between.

**In your PR description**, call out:
- Any element whose parent/ancestor chain changed
- Any user-facing string that moved or was renamed
- Any `data-testid` or stable ID you removed

This lets QA run a targeted check rather than discover it after a regression ships.

## 7. Don't expose flaky state in the DOM

Tests assert on DOM content. Anything visible in the DOM should be deterministic given the
same inputs.

- **Timestamps** — render in a format tests can match, not "2 minutes ago" that changes
  by the second. If you must show relative time, wrap it in `data-timestamp="..."` so
  tests can assert on the underlying value
- **Random ordering** — if you randomize related-product sections, tests will see
  different products each run. Either seed the randomness or let tests opt out (e.g. a
  `?sort=stable` query param)
- **Incremental loading** — if the DOM mutates after initial render, ensure the final
  state is reachable via a deterministic wait (an element appearing, a count stabilizing).
  Avoid "load 5 more every 2 seconds" patterns

## 8. Accessibility and testability are the same problem

Every time you improve accessibility — adding ARIA labels, using semantic HTML, giving
interactive elements accessible names — you also improve testability. The converse is
also true: flaky tests often point at a real a11y bug.

If you're uncertain whether a change breaks tests, run the E2E suite against your branch
before merging. Ask your QA contact for the command.

---

## When in doubt

- Err toward semantic HTML
- Add `data-testid` when semantic roles don't work
- Call out visible DOM changes in your PR description
- Ask QA — catching a regression in review is cheaper than catching it after ship
