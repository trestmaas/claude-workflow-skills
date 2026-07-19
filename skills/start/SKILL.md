---
name: start
description: Execute a single Linear ticket end-to-end hands-off — enters an isolated worktree, sets Linear In Progress, creates a branch following the configured format, writes failing tests against the ticket's acceptance criteria, implements, then calls /ship. Pauses as `needs input:` on any acceptance-criterion ambiguity rather than guessing. Reads `.claude/conventions.yaml` for branch + test conventions.
---

# /start

Take a Linear ticket from "Todo" to "merged" hands-off, in an isolated worktree.

## Conventions

Reads `.claude/conventions.yaml`:

```yaml
linear:
  ticket_prefix: THE
  status:
    in_progress: "In Progress"
branch:
  format: "westmaas/the-{id}-{slug}"
  # Variables: {prefix} (uppercase), {prefix_lower}, {id} (numeric), {slug} (kebab-case)
  # Default: "{prefix_lower}-{id}-{slug}"
test:
  command: "bun run test:run"
  bail: "bun run test:run --bail"
# Default: auto-detect via package manager and package.json scripts.
```

## When to use

- Picking up a single ticket from your active project (or any standalone ticket).
- Called by `/project-start` for each parallel ticket it spawns.

For "I have an idea, scaffold a project around it," use `/project-plan` first.

## Input

The ticket id (e.g. `THE-219`). Can be passed as argument or asked for if missing.

## Steps

### 1. Read the ticket

- `mcp__claude_ai_Linear__get_issue` to pull title, description, acceptance criteria, expected file surface, depends_on.
- If the ticket is part of a planned project (look for `.handoffs/<project-slug>/tickets.yaml` containing this id), read the yaml entry too — it's the authoritative contract.
- Cross-check: do Linear and yaml agree on file surface and acceptance? If they diverge, **pause** `needs input: ticket and handoff yaml disagree on <field>`.
- **Backend-dependency check.** Scan acceptance criteria for endpoint-shaped strings: tRPC procedure names (`viewer.foo.bar`, `organizations.delete`), REST routes (`/api/...`), or service-method calls. For each, grep main for the definition. If any are missing, **pause** `needs input: acceptance implies <endpoint> but it does not exist on main` — listing every missing one. Do NOT stub a "coming soon" toast, do NOT invisibly extend an unrelated router to add the surface yourself. The point of the pause is to let the user rescope the ticket or land the backend in a different ticket first. Project #5's THE-277/THE-279 silently shipped UI pointing at non-existent endpoints because no one checked.

### 2. Enter an isolated worktree

- Try `EnterWorktree` with name `<prefix-lower>-<id>-<short-slug>` (e.g. `the-219-outcome-correlation`). Gives a clean checkout off the default branch and isolates from any parallel siblings.
- **Fallback when `EnterWorktree` refuses** (typical reason: parent of this subagent is already in a worktree, so the harness thinks you're isolated even though you're sharing the parent's checkout):
  - Manually create your own worktree: `git worktree add <repo-root>/.claude/worktrees/<name> -b <branch-name>` where `<repo-root>` resolves via `git rev-parse --show-toplevel` from the parent's repo, NOT the current cwd which may be a worktree.
  - Operate on the new worktree with absolute paths and `git -C <worktree-path>` for every git command. Do NOT `cd` — your cwd belongs to the parent and other siblings depend on its branch state.
  - All file operations (Read / Write / Edit) use absolute paths under the new worktree.
  - The skip of `EnterWorktree`'s normal cleanup also means you must manually `git worktree remove <path>` (or call `ExitWorktree`-equivalent shell cleanup) when `/ship` confirms merge.
- All subsequent work happens in this worktree (or its absolute path) until `/ship` returns merged.

### 3. Set Linear to In Progress

- `mcp__claude_ai_Linear__save_issue` → configured `in_progress` status (default `"In Progress"`). Assign to yourself if not already.

### 4. Create the branch

Apply the configured `branch.format` template (default: `{prefix_lower}-{id}-{slug}`). Generate `{slug}` from the ticket title (kebab-case, drop articles, max ~50 chars).

```bash
git checkout -b <branch-name>
```

### 5. Write failing tests against the acceptance criteria

This is the tests-first step. Drive it with `/tdd` — it's the reference for what a good test is (behavior through public interfaces, reads like a spec, survives refactors), where the **seam** goes (prefer the highest existing seam; the spec already sketched them), and the red→green discipline below. If `CONTEXT.md` exists, read it first so test names and interface vocabulary match the project's pinned glossary.

For each acceptance criterion:
- Identify the test file from the expected file surface (or infer from project test conventions — find the closest sibling test file to the source it's exercising).
- Write a test that asserts the criterion. The test must currently fail (the code that makes it pass doesn't exist yet — that's the point).
- Run `test.bail` (or `test.command` if no `bail` variant) to confirm it fails as expected. If it passes accidentally, the criterion is already met or the test isn't actually testing it — investigate before continuing.

**If the ticket quotes a concrete example, verify it reproduces before you build a test on it.** A plan can ship an example that looks right and doesn't actually trigger the bug (mobile-responsive-fixes did it twice in fifteen tickets — an email whose hyphen let Chrome wrap it, a location string too short to overflow the document). If the ticket's value doesn't reproduce, **find one that does, use it, and say so in your report** — do not quietly assert against a value that was already green.

**Then ask the harder question: what would make my fix inert?**

Red-then-green proves your test detects the **removal** of your code. It does *not* prove your code **does anything**. Those are different claims, and the gap between them is where silent no-ops live.

SIGN-373 added `pb-[env(safe-area-inset-bottom)]` to a fixed bottom bar. Its author falsified all four source changes and every one went red — textbook discipline. The fix was still a **complete runtime no-op**: `env(safe-area-inset-*)` resolves to `0px` unless the document opts into `viewport-fit=cover`, which the app never did. On a real notched phone nothing changed. A class-name assertion is green whether or not the value resolves to anything, and headless CI has no safe area, so neither level of test could see it. (A pre-existing `ui/sheet.tsx` had been inert the same way, for months.)

So, before you call it done:

- Name the capability your fix silently depends on — a viewport meta, a feature flag, a polyfill, a browser API, a CSS feature behind an opt-in, a header, an env var.
- Ask: if that dependency were missing, would *any* of my tests fail? If the honest answer is no, **you have not tested the fix — you have tested that you typed it.**
- Add the assertion that *can* fail: assert the served artifact (the meta tag, the computed value, the resolved pixel), not the source you just wrote.

Commit: `tests: failing tests for <TICKET-ID>`.

### 6. Implement

Write the minimum code to make the tests pass. Match existing style, don't improve adjacent code, surface tradeoffs in one line when making a non-obvious choice.

While implementing, if you hit an acceptance criterion that's **ambiguous** (the criterion as written allows two reasonable interpretations that would produce different code):

- **Pause** with `needs input:` on its own line.
- State what's ambiguous, the two interpretations, and which one you'd pick if forced.
- Do not guess past this point. The whole point of pausing is to avoid silently building the wrong thing in a parallel sub-agent context where the user can't course-correct mid-flight.

If during implementation you discover a missing file from the declared surface (something you need to touch that wasn't listed), note it in a comment on the ticket via `mcp__claude_ai_Linear__save_comment` and continue. After merge, `/project-retro` will surface drift.

**Comment hygiene.** Source comments are for non-obvious WHY (hidden constraint, subtle invariant, workaround for a specific bug) — not for narrating tradeoffs, decisions, or PR context. That belongs in the PR description. Do NOT add file-header block comments explaining "I chose X over Y because Z" or "this ticket implements...". If a future reader of just this file wouldn't be confused by the absence of the comment, don't write it. Project #5 had three sections (THE-280, THE-283, THE-284) land tradeoff narration in source files; the cleanup belongs in the PR body.

Commit code in logical chunks. Run `test.command` between commits — green before each commit.

### 6b. Composition guard

If any acceptance criterion says a child component is **rendered inside / shown in / mounted in** a parent component (e.g. "`SidebarOrgSwitcher` renders inside `SettingsSidebar` between the Developer band and the footer"), grep the parent file for:

1. An import of the child component.
2. A JSX usage of the child somewhere in the return tree.

If either is missing, you haven't finished the ticket — add the import + render call, ensure a structural test asserts the child renders under the right conditions, then re-run the gate.

This catches the "components shipped but never composed" class. Project #3 of the Org UX initiative shipped THE-258 (`SidebarOrgSwitcher`) and THE-259 (`SidebarOrgSections`) as separate components — but `SettingsSidebar.tsx` never imported or rendered them. Unit tests passed (each component had its own), types passed (no caller, no error), individual PR reviews looked fine. The bug only surfaced when a user opened the page and saw a half-built sidebar. Fixed in THE-288 after the fact.

Like the deletion guard, this is a separate explicit step rather than a side-effect of implementation, because the failure mode is silent — tests stay green when a parent doesn't compose its declared children.

### 7. Deletion guard

If any acceptance criterion mentions deleting / retiring / removing specific files (e.g. "Retire legacy components: `src/foo/Bar.tsx`, `src/foo/Baz.tsx` are deleted"), parse out the paths and assert each is gone:

```bash
for f in <paths>; do [ -e "$f" ] && { echo "STILL EXISTS: $f"; exit 1; }; done
```

If any still exist, you have not finished the ticket — go back and delete them, then re-run the gate. Do NOT proceed to `/ship` with declared deletions un-done.

This is a separate, explicit step rather than a side-effect of implementation because deletion criteria are easy to silently skip — the test suite stays green either way. Project #5's THE-287 wired up the admin shell but left all 9 files declared for retire on main; the miss only surfaced post-merge in `/project-retro`.

### 8. Verify (UI / frontend work only)

If the change is UI/frontend, invoke the `verify` skill or otherwise start the dev server and exercise the feature in a browser before declaring it done. Type checking verifies code correctness, not feature correctness.

For pure backend / data work, the test suite is the verification.

### 8b. File any manual tasks you uncovered

If implementing this ticket surfaced work **a human must do outside the repo** — set a Vercel env var, add a DNS record, configure something in a Stripe/Google/OAuth dashboard, rotate a key, flip a flag, sign up for a third-party service, make a call only the user can make — file it per `/manual-tasks` **before** calling `/ship`. Then keep going.

This is not a pause and **not a third way to end**. Step 10's two endings are unchanged. A manual task is deferrable by definition; if it genuinely blocks *you* from finishing the ticket, that is still `needs input:`.

Which channel:

- Can the ticket merge and this be done later? → **file a manual task**, ship normally.
- Do you need an answer before you can write correct code? → **`needs input:`**.

Set the task's priority to Urgent when the code you are about to merge is **inert until the manual step happens** — a feature reading an env var that doesn't exist yet ships green, passes review, and does nothing in prod. That is the exact failure this mechanism exists to catch: say so in the task's "Until then" line, and name the task id in your step-10 report so it isn't only visible in Linear.

### 9. Call /ship

Invoke the `/ship` skill. It handles the gate, push, PR, hand-off to delivery, merge, and worktree cleanup.

If `/ship` pauses with `needs input:`, propagate that up — don't try to fix the underlying issue without confirmation.

### 10. Report

**You have exactly two ways to end. There is no third.**

1. `result: completed <TICKET-ID> — PR #<N> merged` — only after you have **verified the merge yourself** with `gh pr view <N> --json state,mergedAt` and seen `state: "MERGED"`. Not because `/ship` said so. Not because a delivery agent said so. Because you looked.
2. `needs input: <what is blocking>` — anything else.

**"Awaiting merge" is not an ending.** On the multi-calendar project, **5 of 7** `/start` agents returned with some variant of *"Monitor armed, waiting on CI"* / *"handed off to the delivery agent, awaiting its report"* — no `result:`, no `needs input:`, just a status update. Every one forced the orchestrator to re-derive the PR number, poll `gh` itself, and re-drive the ticket. The work was fine; the *ending* was the defect, and it cost a round-trip per ticket.

If CI is still running, **keep waiting** — poll `gh pr view <N> --json state` until it leaves `OPEN`, then report. Blocking is correct behavior; a status-update return is not. If you genuinely cannot wait (auto-merge disabled by a human, CI red, delivery agent dead), that is a `needs input:` with the specific reason — not a shrug.

If invoked by `/project-start`, also signal the parent with the ticket id and final state.

## Failure modes — what counts as `needs input:`

- Ticket has no acceptance criteria, or all of them are vague.
- File surface conflicts with another in-flight ticket that wasn't declared as a depends_on (parent didn't sequence correctly).
- Tests can't be written because the acceptance criterion isn't testable as stated.
- `/ship` reports a blocker (gate failure, CI red, review blocked).

In all of these, pause. Don't pattern-match around it.

## What this skill does NOT do

- Does not skip the failing-tests step. Tests come first.
- Does not modify other tickets, even if you notice an issue.
- Does not delete the worktree — `/ship` handles that on confirmed merge.
- Does not retry merge conflicts via force-push.
