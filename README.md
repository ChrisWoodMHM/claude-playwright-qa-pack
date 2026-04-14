# QA Pack for Claude Code

Drop-in Claude Code skills, hooks, and lint config that enforce 2026 Playwright + TypeScript
best practices.

## What's inside

| Path | What it does |
|---|---|
| `.claude/skills/qa-e2e-authoring/` | Proactive guardrails when Claude edits `*.spec.ts`, page objects, or test utilities. |
| `.claude/skills/qa-review/` | User-invocable `/qa-review` — reviews staged test code against the checklist. |
| `.claude/hooks/block-debug-artifacts.sh` | PostToolUse hook that blocks `test.only`, `page.pause()`, `debugger`, and common secret patterns from being written to spec files. |
| `.claude/settings.json` | Wires the hook. Merge with your existing settings. |
| `eslint/eslint.config.example.mjs` | Drop-in ESLint config for Playwright + TS projects. Catches missing `await` (the #1 flakiness cause) mechanically. |
| `GUIDELINES.md` | Short dev-facing reference: how to write application code that stays testable. |
| `USAGE.md` | Workflow guide for test authors (human and AI): when to invoke `/qa-review`, how to triage failures, PR checklist. |

## Install (per project)

From the root of the project you want to instrument:

```bash
# 1. Copy skills and hook into the project
cp -r /path/to/qa-pack/.claude/skills/qa-e2e-authoring .claude/skills/
cp -r /path/to/qa-pack/.claude/skills/qa-review .claude/skills/
mkdir -p .claude/hooks
cp /path/to/qa-pack/.claude/hooks/block-debug-artifacts.sh .claude/hooks/
chmod +x .claude/hooks/block-debug-artifacts.sh

# 2. Merge hook config into .claude/settings.json
# (see .claude/settings.json in this pack for the snippet)

# 3. Install ESLint plugins and drop in the config
npm install -D typescript-eslint eslint-plugin-playwright
cp /path/to/qa-pack/eslint/eslint.config.example.mjs eslint.config.mjs
```

## Install (user-level, all projects)

To apply to every project you work on, copy into `~/.claude/`:

```bash
cp -r /path/to/qa-pack/.claude/skills/* ~/.claude/skills/
cp /path/to/qa-pack/.claude/hooks/block-debug-artifacts.sh ~/.claude/hooks/
# merge settings.json snippet into ~/.claude/settings.json
```

## What each skill enforces

**qa-e2e-authoring** (auto-activates on `*.spec.ts`, `tests/pages/*.ts`):
- Every async Playwright call is `await`ed
- Locator hierarchy: `getByRole` > `data-testid` > stable class > tag+attr
- Web-first auto-retrying assertions (no `expect(await locator.textContent())`)
- No `page.waitForTimeout()`, no `networkidle`
- `test.step()` structure, data-driven `for...of` + `test.describe`
- Visual-test stability: disable animations, hide overlays, pause videos

**qa-review** (invoked via `/qa-review [path]`):
- Post-hoc review of staged test changes against the full checklist
- Severity-graded output (CRITICAL / WARNING / STYLE)
- Ends by asking whether to apply fixes

## Verifying it works

After install, try editing a `*.spec.ts` file in Claude Code. You should see the skill's rules
applied before code is written. Then deliberately ask Claude to add a `test.only()` — the hook
should block the write with a visible error.

## Maintaining

- **Skills** are plain markdown. Edit freely; changes apply on the next Claude Code session.
- **Hook** is a shell script. Edit the `BLOCK_PATTERNS` array to add checks.
- **ESLint** — run `npm run lint` to verify. The `no-floating-promises` rule requires
  type-aware parsing (configured in the pack's config).

Version 1.0 — April 2026
