---
name: project-retro
description: Post-project writeup with quality signals for hands-off execution. Pulls timing and reopens from Linear; revert/fixup signals from gh; checks its recommendations against prior retros so findings aren't re-derived. Writes a Linear document attached to the project, and lands the mechanisable recommendations itself as skill-file PRs and follow-up tickets. Called automatically by /project-start on full completion, or manually after any project closes.
---

# /project-retro

Generate a short retro doc for a completed project. Three purposes:

1. **Project record** — what shipped, what slipped, what got deferred.
2. **Hands-off execution telemetry** — quality signals that tell us whether `/project-start`'s parallel execution is producing trustworthy code over time. This is how we judge "did hands-off work?"
3. **Change something** — land the recommendations that can be mechanised, rather than writing them down for a later retro to write down again.

## When to use

- Automatically called by `/project-start` on all-tickets-merged.
- Manually after any project closes, including ones that didn't go through `/project-start`.

## Input

Project slug, name, or id.

## Conventions

Optional `.claude/conventions.yaml` fields:

```yaml
linear:
  ticket_prefix: THE          # used to match branches like <login>/the-219-... to project tickets
branch:
  format: "{user}/{prefix_lower}-{id}-{slug}"   # used to identify PRs belonging to project tickets; {user} = GitHub login
```

## Signals to gather

### From Linear (`mcp__claude_ai_Linear__*`)

- `completedAt - startedAt` for the project (wall-clock duration).
- For each ticket in the project:
  - `completedAt - startedAt` per ticket.
  - **Reopens:** count of status transitions from a Done-type state back to a non-Done state. Indicates the agent shipped something that needed revisiting.
  - **Comments:** read them, don't count them — under hands-off execution most are the orchestrator posting scope corrections. Extract the **human** interventions; see the blind-signals note below.
- **Manual tasks:** open issues labelled `manual` created between the project's `startedAt` and `completedAt`. These are the human-only prerequisites the project uncovered; any still open means some of what shipped may not be live. Worth a retro line even when the code all merged clean.

### From git + gh

Identify PRs by branch convention from `branch.format` (matching `{id}` against each project ticket id).

For each PR:

- **Time to merge:** PR open → merged. A throughput number, not a quality one — auto-merge arming makes it arbitrarily small.
- **Reverts:** `git log --since=<project completedAt> --grep="Revert"` and check for any revert of this PR's squash commit. Match on subject lines: a PR body describing red-before-green will hit the grep and is not a revert.
- **Fixup commits:** `git log --since=<merge time> --until=<+7 days> -- <files touched by the PR>` looking for commits referencing the same ticket id or touching the same surface — proxy for "had to come back and fix it."
- **Files actually touched** vs **files declared** in `tickets.yaml`. Diff to surface drift. The declared surface is a sequencing input, not a scope contract — read drift for what it says about the *plan*, not about the agent.

### Signals that are structurally blind — don't report them as quality

Three metrics earlier versions of this skill emitted have measured nothing for months, and said so in the retro text while still being printed. Report them only as below.

- **`gh pr view --json reviews` returns 0 on every PR** when review runs as an agent rather than a GitHub review object. Don't print a "mean review iterations" derived from it. Report instead, from the run itself: **independent-review verdicts** (blocking / should-fix / clean), **fix rounds per PR**, and **what self-review caught that independent review did not**. That last number has been ~0 on every measured project; if it is ever non-zero, that is the finding.
- **First-push CI pass rate is not recoverable after the fact.** `gh run rerun` overwrites a run's conclusion in place and any rebase re-runs CI, so a late reconstruction reads green for runs that failed. Capture it live during the run or mark it `n/a`. Never read it as quality on gate, contract, or projection work — there the check *is* the deliverable, so the suite is blind to it by construction. A project has shipped 100% first-push green carrying a live credential leak.
- **Comment volume is inverted under hands-off execution.** Most comments are the orchestrator posting scope corrections, which is the system working. Count **human interventions mid-flight** instead, and report orchestrator scope notes separately.

### From prior retros — required before writing recommendations

Prior recommendations are a signal, and not reading them is how the same finding gets re-derived from scratch ten times.

List the last ~10 retro documents (`mcp__claude_ai_Linear__list_documents` with `query: "retro"`, ordered by `createdAt`) and read their **Recommendations** sections. For each recommendation you are about to write, establish:

- **Has this been recommended before, and how many times?** If yes, say so in the recommendation itself — "third retro to raise this" is a stronger finding than the recommendation. Don't re-propose it in fresh language as though it were new.
- **Does this contradict a prior recommendation?** If so, treat it as a reversal and say what new evidence overturns the old one. **One clean project is not evidence.** A prior recommendation backed by a measured before/after may not be reversed on a single run that happened to go well — that reversal has been made once, on a sample of one, and was refuted a week later at the cost of a month of re-derivation. Prefer "the prior fix held and this run adds a second layer" over "downgrade the prior fix".

### From `/project-start` runtime (if available)

`/project-start` writes `.handoffs/<slug>/runtime.log` (one line per `spawn` / `review` / `merge` / `paused` / `killed`). If it exists, include the items below, and use its `review` lines for the independent-review verdicts. A PR with a `merge` line and no `review` line is a finding.

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
| Independent-review verdicts | N blocking / N should-fix / N clean | the load-bearing number |
| Blocking defects self-review caught | N | ~0 on every project so far; non-zero is the finding |
| Mean fix rounds per PR | N | <flag if >2> |
| Reverts | N | <list if >0> |
| Fixup commits within 7d | N | <list with ticket-id refs> |
| Ticket reopens | N | <list> |
| Human interventions mid-flight | N | <what and why; orchestrator scope notes counted separately> |
| Premises patched before release | N/M dependents | <agents that lost a lifecycle to a stale premise> |
| False verification found | N | <tests/fixtures/harnesses that passed while proving nothing> |
| Plan drift (files declared vs touched) | N tickets with drift | <list with diffs> |
| Mean time to merge | X min | throughput, not quality |
| First-push CI pass rate | X/Y or `n/a` | `n/a` unless captured live; not a quality signal on gate/contract work |

## Tickets that needed intervention

<for each paused/failed ticket: id, reason, how it was resolved>

## Manual tasks this project left open

<for each still-open manual task filed during this project's window: id, one line, and whether shipped code is inert until it's done. "None." if clean.>

## Recommendations for next time

<2–4 bullets. Pattern-spot across the signals above.

For each pattern, draft the narrow recommendation first — the one that just
restates what happened — then widen it until it would still have been *wrong*
had the signal come out differently. Ship the widest version that still fully
accounts for what you saw. Stay between the two failure modes:

- Too narrow: "drop concurrency to 2 for projects touching src/lib/db.ts."
  True, but fires on almost no future project.
- Too wide: "watch out for merge conflicts." Fires on everything, so it
  changes nothing.
- About right: "auto-sequence any file that appears in more than one ticket's
  declared surface." Covers db.ts and everything like it, and is still
  falsifiable — had the conflicts been in files each declared by a single
  ticket, this wouldn't have been the fix.

A recommendation that couldn't have come out differently isn't a finding.

Then classify each one by **where it lands**, and write the landing into the
recommendation:

- **Mechanism** — a gate, test, lint rule, type, helper, or an edit to a skill
  file. Something fails if it stops being true.
- **Prompt** — a line in a brief, a habit, a thing an agent is told to remember.
  Nothing fails if it stops being true.

Every mechanism-level recommendation in this corpus appeared once and never
again. Every prompt-level one recurred 5–12 times over five months, including
one that an agent was explicitly told and did anyway. So: if a recommendation
lands as prompt text, either convert it to a mechanism or state plainly in the
retro that it will recur. Don't write the wish and move on.

Examples:>
- "Auth-related tickets keep drifting outside declared file surface — bake a check into /project-plan that prompts for cross-cutting paths." *(mechanism: skill-file edit — applied, see below)*
- "Fourth retro to raise that agent-run reviews leave no GitHub record. Prompting has not fixed it; the mechanism is one flag on the review call." *(mechanism: skill-file edit)*
- "Agents should re-derive counts rather than trust a ticket's enumeration." *(prompt — will recur until the AC names the derivation instead of the number)*
```

## Apply the mechanism-level recommendations

Writing the recommendation down is what has been failing. After the doc is written, **land the mechanisable ones yourself** — don't ask first, and don't leave them as a wish for a future run to rediscover.

In scope, no confirmation needed:

- **Edit the workflow skill files** (`project-plan`, `project-start`, `ship`, `start`, and this one) in the skills repo, when the recommendation is a change to what those skills instruct or check.
- **File Linear tickets** for gates, guards, ratchets, and lint rules that belong in the product repo — with the falsification already stated, so the ticket is buildable.
- **Update `.claude/conventions.yaml`** for facts about the repo the run discovered (an unsafe flag, a lane that can't run locally, a gate that isn't what it looks like).

Out of scope — surface as a recommendation and stop:

- Product code, schema, or anything that changes user-visible behaviour.
- Reversing a decision a human made, including one made during this project.
- Anything outward-facing or hard to undo: pushing to `main`, merging, dashboards, third-party config, spend.

**How to land a skill edit:** branch, commit, open a **draft PR** against the skills repo — never push to `main`. One PR per retro, titled for the project. Put the retro's own reasoning in the PR body so the change is reviewable without re-reading the retro.

Then add a section to the retro doc:

```markdown
## Applied

- <what changed, where, and the PR link> — from recommendation N.
- <ticket filed, with id and one line> — from recommendation N.

## Not applied

- <recommendation N> — <why it needs a human: product behaviour / a decision / out of scope>.
```

If nothing was mechanisable this run, say `## Applied\n\nNothing — all N recommendations are prompt-level. Expect them to recur.` That sentence is itself a finding worth seeing twice.

## Telemetry posture

This skill keeps everything in **Linear + git + gh**. No external dashboards. The retro doc is the deliverable.

If a pattern starts mattering longitudinally (e.g., "we want to track first-push CI pass rate across all projects over time"), *then* extend this skill to emit events to your analytics tool of choice. Don't pre-build the pipeline.

## What this skill does NOT do

- Does not modify the project's own tickets or PRs. Read-only against the project under retro; the writes it makes are the Linear doc, new follow-up tickets, and skill-file PRs (see **Apply**).
- Does not touch product code, or reverse a decision a human made.
- Does not score the agent or shame past decisions. Signals + recommendations, not blame.
- Does not invent reverts/fixups that aren't in the git history. If a signal is unavailable, mark it `n/a` and move on — `n/a` is a better answer than a reconstructed number.

## Report

Final line: `result: retro written for <project-name> — <doc URL>`, plus the skills PR link and any ticket ids if anything was applied.
