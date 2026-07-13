---
name: ship
description: Take one ticket's local working state from "code written" to "merged" hands-off. Runs the project's pre-push gate, pushes, opens a PR titled with the ticket id, sets Linear to In Review, hands off to a delivery agent (or inline review + merge if none configured). Reads `.claude/conventions.yaml` for project specifics; falls back to package-manager auto-detection. Worktree is kept until merge confirmed.
---

# /ship

Take the current branch from "code written" to "merged" hands-off.

## Conventions

This skill is part of the `workflow-skills` set. It reads `.claude/conventions.yaml` at the project root for per-project specifics; everything else falls back to defaults.

Fields it cares about:

```yaml
linear:
  ticket_prefix: THE                 # e.g. THE-219. Default: auto-detect from recent branches.
  status:
    in_review: "In Review"            # Default: "In Review"
    done: "Done"                      # Default: "Done"

gate:                                 # commands run in order; each must pass
  - <package-manager> run lint
  - <package-manager> run typecheck
  - <package-manager> run test
  - <package-manager> run build
# Default: auto-detect bun/pnpm/yarn/npm from lockfile + package.json scripts and run
# whichever of lint/typecheck/test/build exist.

delivery:
  agent: code-delivery-orchestrator   # subagent_type to spawn after PR creation
# Default: skill inlines /code-review (two-axis) + /security-review then watches `gh pr checks` until green and merges.
```

If no `.claude/conventions.yaml` exists, infer everything. Surface what you inferred in your first status message ("inferred gate: pnpm run lint, pnpm run typecheck, pnpm run build").

## When to use

- A coding session is finished on a branch tagged with a ticket id and you want to ship it.
- Called automatically by `/start` at the tail of a single-ticket execution.
- Manually invoked when you finished a ticket without going through `/start`.

## Preconditions

- Current branch name contains the configured `ticket_prefix-<id>` (e.g. `westmaas/the-219-...` or `THE-219-feature`).
- At least one test file was added or modified. If no test changed, **pause** with `needs input:` — every ship goes out with tests.
- All intended changes are committed locally.

If any precondition fails, stop. Do not proceed with partial state.

## Steps

### 1. Sanity check

- Read `.claude/conventions.yaml` (if present). Apply defaults for anything missing.
- Extract the ticket id from the current branch name (regex: `(?i)\b<prefix>-(\d+)\b`). If none, pause `needs input: branch name doesn't contain a Linear ticket id`.
- `git status` — confirm working tree clean. If not, pause `needs input: uncommitted changes, commit or stash first`.
- `git diff <base>...HEAD --name-only` — confirm at least one test file changed (heuristic: matches `*.test.*`, `*.spec.*`, `tests/`, `e2e/`, `__tests__/`). If not, pause `needs input: no test changes detected, every ship needs tests`. Use the repo's default branch as `<base>` (detect via `gh repo view --json defaultBranchRef`).

### 2. Run the pre-push gate

Run the configured `gate:` commands sequentially. If unconfigured, auto-detect:

- Determine package manager: `bun.lockb` → bun; `pnpm-lock.yaml` → pnpm; `yarn.lock` → yarn; `package-lock.json` → npm.
- For each of `lint`, `typecheck` (or `type-check` or `tsc`), `test:run` (or `test`), `build` — if the script exists in `package.json` `scripts`, run it.

If any step fails:
- Report which step failed and the relevant error output.
- **Pause** with `needs input:` — do not push, do not auto-fix without confirmation. The gate failing usually means something real.

### 3. Push

```bash
git push -u origin HEAD
```

If push fails (rejected, divergent history, etc.), pause `needs input:` with the error. Do not force-push.

### 4. Open the PR

- Fetch the Linear ticket via `mcp__claude_ai_Linear__get_issue` using the ticket id. Pull title + description for the PR body.
- Title format: `<verb summary> (<TICKET-ID>)`. Match the convention of recent merged PRs in the repo (`gh pr list --state merged --limit 5 --json title`).
- Body format:

  ```
  ## Summary
  <1–3 bullets describing what changed and why>

  ## Linear
  <TICKET-ID> — <ticket title>

  ## Test plan
  - [ ] <bullet list of what to verify>

  🤖 Generated with [Claude Code](https://claude.com/claude-code)
  ```

- Create via `gh pr create --title "..." --body "$(cat <<'EOF' ... EOF)"` (HEREDOC for formatting).
- **Always queue `gh pr merge <N> --auto --squash` immediately after creating the PR.** This is the auto-merge handoff — GitHub merges when all checks pass, no further `/ship` action required. Retry once with 2s backoff on the transient `enablePullRequestAutoMerge` GraphQL error (observed across multiple projects; succeeds on immediate retry). If the second attempt also fails, surface the error but continue — the orchestrator will queue auto-merge defensively when it sees the open PR.

### 5. Set Linear to In Review

Use `mcp__claude_ai_Linear__save_issue` with the ticket id and the configured `in_review` status (default `"In Review"` — look up via `mcp__claude_ai_Linear__list_issue_statuses` if uncertain).

Add a comment on the ticket with the PR URL via `mcp__claude_ai_Linear__save_comment`.

### 6. Hand off to delivery

If `delivery.agent` is configured, spawn that subagent with a prompt like:

```
PR #<N> on branch <branch-name> is ready for delivery. Linear ticket <TICKET-ID> is In Review.
Run /code-review against the PR base branch (matt's two-axis Standards + Spec skill, NOT the built-in /review) and /security-review, then watch CI to green and merge (squash). On merge, return control.
Before trusting either review, CONFIRM IT TARGETED THIS PR'S DIFF — see "Assert the review targeted the right diff" below.
```

Run in the **foreground** so `/ship` blocks until merged.

If no delivery agent is configured, inline:
1. Run `/code-review` against the PR's base branch as the fixed point — its two axes (Standards: does the diff follow this repo's documented standards? Spec: does it faithfully implement the ticket?) are the right lens for a single-ticket PR, and its parallel sub-agents keep the two reviews from polluting each other's context. This is matt's `/code-review` skill, not the built-in `/review`.
2. Run `/security-review`.

### 6b. Assert the reviews actually ran

**Before asking whether a review targeted the right diff, confirm it produced output at all.** A skipped review and a passed review look identical in a delivery agent's summary — both end with the PR merging and nobody objecting.

On the multi-calendar project, PR #502's delivery agent returned **twice** without producing `/code-review` or `/security-review` output, reported delivery as complete, and the PR merged with **zero** review coverage. It was the PR that introduced the first user-controlled `calendarId` and `connectionId` — the exact diff most needing a security pass. Nothing failed. Nothing was flagged. The reviews simply never happened, and the summary read the same as if they had.

This matters because reviews on that project were not a formality: across four PRs they caught **six real bugs that fully green test suites missed**, including an account-takeover race (`signIn.social` chosen off an in-flight query result) and a total-failure condition that could never fire, silently rendering an empty grid over a calendar the app could not read.

So, before proceeding:

1. **Point at the artifact.** Each review must have produced findings — including an explicit "no findings" verdict with the confidence bar stated. "The delivery agent said it ran" is not evidence.
2. If either review produced **no output**, it did **not** run. Re-run it yourself. Do not merge on the assumption that silence means clean.
3. If you cannot obtain review output, treat coverage as **not done**, say so explicitly in your report, and pause `needs input:` rather than merging a PR whose review status you cannot state.

Never let "no findings reported" and "no review performed" collapse into the same sentence.

### 6c. Assert the review targeted the right diff

**`/security-review` and `/code-review` resolve "the current branch" from the working directory — which in a multi-agent or worktree setup is not necessarily your PR's branch.**

On the Public org events catalog run (SIGN-344), `/security-review` silently reviewed `westmaas/agent-skills-setup` — an unrelated docs-only branch that the *main checkout* happened to be sitting on — instead of PR #492's diff. It **exited cleanly and produced a confident, entirely irrelevant result.** A security review that silently targets the wrong diff is worse than no security review: it manufactures false assurance. (The `security-guidance` plugin's own README warns its diff review is unreliable in "multi-agent / shared-worktree setups where another agent can move HEAD between a worker's turns.")

Before accepting any review output:

1. Confirm the review's reported target matches this PR. Establish ground truth with `git -C <worktree> rev-parse --abbrev-ref HEAD` and `gh pr view <N> --json headRefName`.
2. If the review names a different branch — or names no branch at all — **discard its output** and re-run it explicitly scoped to the PR's diff (e.g. against `origin/<base>...<pr-branch>`, or from inside the PR's worktree).
3. If you cannot establish what a review actually looked at, treat that ticket's review coverage as **not done** and say so in your report. Never report "security review passed" on an unverified target.
3. Address any high-confidence findings or pause `needs input:` with them.
4. Watch `gh pr checks <N> --watch` (or poll every 3 minutes) until green.
5. `gh pr merge <N> --squash --auto` (if `gh pr merge --auto` is supported on this repo) or `gh pr merge <N> --squash` directly.

### 6a. Block on merge confirmation before returning

**Do not return from `/ship` until the PR is confirmed merged.** This was the most-recurring class of bug across project retros — subagents returning with "Monitor armed, awaiting CI" or a review-summary tail before merge actually completed, then the orchestrator had to do defensive recovery.

After step 6 hands off, poll:

```bash
gh pr view <N> --json mergedAt,state --jq '.mergedAt'
```

- Returns a timestamp (non-null) → merged. Continue to step 7.
- Returns `null` and `state == "OPEN"` → not merged yet. Wait 10s, poll again.
- Returns `null` and `state == "CLOSED"` → closed without merge. Pause `needs input: PR #<N> closed without merge — investigate.`

Ceiling: ~10 minutes of polling. If not merged by then, pause `needs input: PR #<N> not merged after 10 min — CI may be stuck, or auto-merge isn't firing. Manual intervention required.`

This loop blocks the foreground; that's intentional. The orchestrator's concurrency cap means at most N `/ship` calls are blocked-on-merge at once, which is fine.

### 7. On merge — mark Linear Done, clean up worktree

- `mcp__claude_ai_Linear__save_issue` → configured `done` status (default `"Done"`).
- If the current cwd is inside `.claude/worktrees/`, call `ExitWorktree` with `action: "remove"` to clean up. Otherwise leave the working tree as-is.
- If this `/ship` was invoked by `/project-start`, notify the parent with the ticket id and merged status so it can release dependents.

### 8. Report

Final line: `result: shipped <TICKET-ID> — PR #<N> merged`.

## Failure modes — what counts as `needs input:`

- Gate fails — do not auto-fix without confirmation.
- Push rejected (divergent, protected branch) — never force-push.
- Delivery reports CI stuck red after retries, review-blocked, or merge conflict it can't resolve.
- Linear ticket doesn't exist or you don't have write access.

In all of these, write `needs input:` on its own line with the specific blocker. Do not retry in a loop.

## What this skill does NOT do

- Does not write code or fix failing tests. The premise is code is already written.
- Does not run `git add` / `git commit`. Commits should already exist.
- Does not amend or rewrite commits.
- Does not delete the local branch after merge. Leave it for the user.
