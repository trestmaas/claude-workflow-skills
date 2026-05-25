---
name: project-retro
description: Post-project writeup with quality signals for hands-off execution. Pulls timing and reopens from Linear; revert/fixup/CI/review signals from gh. Writes a Linear document attached to the project. Called automatically by /project-start on full completion, or manually after any project closes.
---

# /project-retro

Generate a short retro doc for a completed project. Two purposes:

1. **Project record** — what shipped, what slipped, what got deferred.
2. **Hands-off execution telemetry** — quality signals that tell us whether `/project-start`'s parallel execution is producing trustworthy code over time. This is how we judge "did hands-off work?"

## When to use

- Automatically called by `/project-start` on all-tickets-merged.
- Manually after any project closes, including ones that didn't go through `/project-start`.

## Input

Project slug, name, or id.

## Conventions

Optional `.claude/conventions.yaml` fields:

```yaml
linear:
  ticket_prefix: THE          # used to match branches like westmaas/the-219-... to project tickets
branch:
  format: "westmaas/the-{id}-{slug}"   # used to identify PRs belonging to project tickets
```

## Signals to gather

### From Linear (`mcp__claude_ai_Linear__*`)

- `completedAt - startedAt` for the project (wall-clock duration).
- For each ticket in the project:
  - `completedAt - startedAt` per ticket.
  - **Reopens:** count of status transitions from a Done-type state back to a non-Done state. Indicates the agent shipped something that needed revisiting.
  - **Comment volume:** number of comments on the ticket. High comment volume on a hands-off ticket signals that the human had to intervene mid-flight.

### From git + gh

Identify PRs by branch convention from `branch.format` (matching `{id}` against each project ticket id).

For each PR:

- **First-push CI pass rate:** did the pre-push gate pass on the first push? Check via `gh pr checks <N>` history or `gh run list --branch <branch>`.
- **Review iterations:** distinct review comments / requested-changes events (`gh pr view <N> --json reviews`).
- **Time to merge:** PR open → merged.
- **Reverts:** `git log --since=<project completedAt> --grep="Revert"` and check for any revert of this PR's squash commit.
- **Fixup commits:** `git log --since=<merge time> --until=<+7 days> -- <files touched by the PR>` looking for commits referencing the same ticket id or touching the same surface — proxy for "had to come back and fix it."
- **Files actually touched** vs **files declared** in `tickets.yaml`. Diff to surface drift.

### From `/project-start` runtime (if available)

If a runtime log exists at `.handoffs/<slug>/runtime.log` (future enhancement — `/project-start` could emit one), include:

- Tickets that paused as `needs input:` and the reason.
- Auto-sequenced file-surface conflicts that were caught.
- Total wall-clock execution time vs sum of per-ticket times (parallelism factor).

If no runtime log, skip this section.

## Output

Write a Linear document attached to the project via `mcp__claude_ai_Linear__save_document` with `project` set to the project id. Title: `Retro — <project name>`.

Document structure:

```markdown
# Retro — <project name>

**Duration:** <startedAt> → <completedAt> (<N> days)
**Tickets:** <merged>/<total> merged, <paused>/<failed> needing intervention

## What shipped
- <one line per ticket, with PR link>

## What slipped or got deferred
- <ticket or scope item that was cut, with reason if known>

## Quality signals (hands-off execution)

| Metric | Value | Notes |
|--------|-------|-------|
| First-push CI pass rate | X/Y PRs (Z%) | <flag if <80%> |
| Mean review iterations | N | <flag if >2> |
| Mean time to merge | X hours | |
| Reverts | N | <list if >0> |
| Fixup commits within 7d | N | <list with ticket-id refs> |
| Ticket reopens | N | <list> |
| Comment volume (mean per ticket) | N | <flag tickets with >5> |
| Plan drift (files declared vs touched) | N tickets with drift | <list with diffs> |

## Tickets that needed intervention

<for each paused/failed ticket: id, reason, how it was resolved>

## Recommendations for next time

<2–4 bullets. Pattern-spot across the signals above. Examples:>
- "Auth-related tickets keep drifting outside declared file surface — bake a check into /project-plan that prompts for cross-cutting paths."
- "Tickets with >3 acceptance criteria had 2x the review iterations — consider splitting at planning time."
- "Concurrency 3 caused two merge conflicts on src/lib/db.ts — that file is a hotspot; drop to 2 for projects touching it."
```

## Telemetry posture

This skill keeps everything in **Linear + git + gh**. No external dashboards. The retro doc is the deliverable.

If a pattern starts mattering longitudinally (e.g., "we want to track first-push CI pass rate across all projects over time"), *then* extend this skill to emit events to your analytics tool of choice. Don't pre-build the pipeline.

## What this skill does NOT do

- Does not modify project, ticket, or PR state. Read-only against Linear / git / gh, write-only to a Linear document.
- Does not score the agent or shame past decisions. Signals + recommendations, not blame.
- Does not invent reverts/fixups that aren't in the git history. If a signal is unavailable, mark it `n/a` and move on.

## Report

Final line: `result: retro written for <project-name> — <doc URL>`.
