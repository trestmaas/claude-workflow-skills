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

### 2. Enter an isolated worktree

- `EnterWorktree` with name `<prefix-lower>-<id>-<short-slug>` (e.g. `the-219-outcome-correlation`). Gives a clean checkout off the default branch and isolates from any parallel siblings.
- All subsequent work happens in this worktree until `/ship` returns merged.

### 3. Set Linear to In Progress

- `mcp__claude_ai_Linear__save_issue` → configured `in_progress` status (default `"In Progress"`). Assign to yourself if not already.

### 4. Create the branch

Apply the configured `branch.format` template (default: `{prefix_lower}-{id}-{slug}`). Generate `{slug}` from the ticket title (kebab-case, drop articles, max ~50 chars).

```bash
git checkout -b <branch-name>
```

### 5. Write failing tests against the acceptance criteria

This is the tests-first step.

For each acceptance criterion:
- Identify the test file from the expected file surface (or infer from project test conventions — find the closest sibling test file to the source it's exercising).
- Write a test that asserts the criterion. The test must currently fail (the code that makes it pass doesn't exist yet — that's the point).
- Run `test.bail` (or `test.command` if no `bail` variant) to confirm it fails as expected. If it passes accidentally, the criterion is already met or the test isn't actually testing it — investigate before continuing.

Commit: `tests: failing tests for <TICKET-ID>`.

### 6. Implement

Write the minimum code to make the tests pass. Match existing style, don't improve adjacent code, surface tradeoffs in one line when making a non-obvious choice.

While implementing, if you hit an acceptance criterion that's **ambiguous** (the criterion as written allows two reasonable interpretations that would produce different code):

- **Pause** with `needs input:` on its own line.
- State what's ambiguous, the two interpretations, and which one you'd pick if forced.
- Do not guess past this point. The whole point of pausing is to avoid silently building the wrong thing in a parallel sub-agent context where the user can't course-correct mid-flight.

If during implementation you discover a missing file from the declared surface (something you need to touch that wasn't listed), note it in a comment on the ticket via `mcp__claude_ai_Linear__save_comment` and continue. After merge, `/project-retro` will surface drift.

Commit code in logical chunks. Run `test.command` between commits — green before each commit.

### 7. Verify (UI / frontend work only)

If the change is UI/frontend, invoke the `verify` skill or otherwise start the dev server and exercise the feature in a browser before declaring it done. Type checking verifies code correctness, not feature correctness.

For pure backend / data work, the test suite is the verification.

### 8. Call /ship

Invoke the `/ship` skill. It handles the gate, push, PR, hand-off to delivery, merge, and worktree cleanup.

If `/ship` pauses with `needs input:`, propagate that up — don't try to fix the underlying issue without confirmation.

### 9. Report

Final line (after `/ship` returns merged): `result: completed <TICKET-ID> — PR #<N> merged`.

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
