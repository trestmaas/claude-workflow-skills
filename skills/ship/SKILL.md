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
# Default: skill inlines /review + /security-review then watches `gh pr checks` until green and merges.
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

### 5. Set Linear to In Review

Use `mcp__claude_ai_Linear__save_issue` with the ticket id and the configured `in_review` status (default `"In Review"` — look up via `mcp__claude_ai_Linear__list_issue_statuses` if uncertain).

Add a comment on the ticket with the PR URL via `mcp__claude_ai_Linear__save_comment`.

### 6. Hand off to delivery

If `delivery.agent` is configured, spawn that subagent with a prompt like:

```
PR #<N> on branch <branch-name> is ready for delivery. Linear ticket <TICKET-ID> is In Review.
Run /review and /security-review, then watch CI to green and merge (squash). On merge, return control.
```

Run in the **foreground** so `/ship` blocks until merged.

If no delivery agent is configured, inline:
1. Run `/review`.
2. Run `/security-review`.
3. Address any high-confidence findings or pause `needs input:` with them.
4. Watch `gh pr checks <N> --watch` (or poll every 3 minutes) until green.
5. `gh pr merge <N> --squash --auto` (if `gh pr merge --auto` is supported on this repo) or `gh pr merge <N> --squash` directly.

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
