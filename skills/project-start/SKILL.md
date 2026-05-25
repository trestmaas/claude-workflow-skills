---
name: project-start
description: Execute a planned project hands-off in parallel. Reads `.handoffs/<slug>/tickets.yaml`, builds a DAG from explicit depends_on edges plus auto-sequenced file-surface conflicts, then spawns up to N (default 3) background /start agents — releasing dependents as tickets merge. Pauses individual tickets as needs input without halting others. On all-done, calls /project-retro.
---

# /project-start

Take a project that's been `/project-plan`ned and execute it end-to-end, parallel, hands-off.

## Preconditions

- **Must NOT be running from inside a worktree.** Check: `pwd` must NOT contain `.claude/worktrees/`. If it does, pause `needs input: /project-start cannot run from inside a worktree — child /start agents inherit "in a worktree" and EnterWorktree refuses, causing branch-flip clobbering between siblings. Exit the worktree (or start a fresh session in the main checkout) and re-run.`
  - Why: child `/start` subagents call `EnterWorktree` to isolate. `EnterWorktree` refuses if its caller is already in a worktree (the parent's). So children fall back to sharing the parent's checkout and `git checkout -b` collisions corrupt working trees and commits land on wrong branches.
  - First-run lesson: this caused the THE-247 clobber + THE-246/THE-252 ad-hoc recovery in project #2's first attempt.
- A `.handoffs/<project-slug>/tickets.yaml` exists. If not: pause `needs input: no handoff bundle for <project>, run /project-plan first`.
- The Linear project is in `Backlog` or `Planned`. If it's already `In Progress`, ask whether to resume or restart.

## Input

The project slug, name, or Linear project id. Resolve to a slug via `mcp__claude_ai_Linear__list_projects` + match.

## Steps

### 1. Load the contract

- Read `.handoffs/<slug>/tickets.yaml`.
- Validate every ticket has an id (filled in during `/project-plan`). If any are missing, pause `needs input: ticket(s) without Linear id — was /project-plan completed?`.
- Read the `concurrency` field. Default `3`.

### 1a. Reconcile with Linear (resume support)

The orchestrator may be resuming a project that's partially shipped (e.g. a previous run shipped some tickets, hit a bug, you fixed it, now you re-run). Query Linear status for each ticket via `mcp__claude_ai_Linear__get_issue` and classify:

- **`Done` / `Completed`** → mark as already-merged in local DAG state. Do NOT spawn `/start` for it. Dependents that only blocked on this ticket are immediately releasable.
- **`In Progress` / `In Review`** → another session (or a previous run that didn't exit cleanly) may still be working it. Treat as **paused** for this run — do NOT spawn `/start` (would collide on branch + PR). Surface to the user: "<TICKET-ID> is <status> in Linear — skipping. If stale, flip it back to Backlog and re-run."
- **`Backlog` / `Todo`** → normal candidate; eligible for the ready set per the DAG.
- **`Canceled`** → treat as merged for DAG purposes (dependents released). The ticket was deliberately removed from scope.

Surface a one-line resume summary before continuing:

```
[project-start] resuming <project-slug> — N done, M in-flight (skipped), K backlog/todo (eligible), P canceled
```

If every ticket is already Done, jump straight to `/project-retro` and mark the project Completed — there's nothing to spawn.

### 2. Build the DAG

For each ticket:

- **Explicit edges:** every entry in `depends_on` is a hard edge.
- **Implicit edges (auto-sequenced):** if ticket A and ticket B both list overlapping paths in `files` and neither depends on the other, add the implicit edge `B depends_on A` (or vice versa — pick the one with lower ticket-id number for determinism). Log the auto-sequence to the user so they can override.
- Detect cycles. If a cycle exists, pause `needs input: dependency cycle detected: <cycle>`.

Compute the ready set: tickets with no unresolved dependencies.

### 3. Flip the project to In Progress

- `mcp__claude_ai_Linear__save_project` → status `In Progress`, `startedAt` = now.

### 4. Schedule and run

This is the parallel-execution loop. Conceptually:

```
running = []
ready = initial ready set

while ready or running:
  while len(running) < concurrency and ready:
    ticket = ready.pop()
    spawn `/start <ticket.id>` as a BACKGROUND subagent
    running.append(ticket)

  wait for any running subagent to complete (you'll be notified — don't poll)

  for each completed:
    if result == merged:
      mark ticket Done in our local state
      release any dependents whose remaining deps are now empty into `ready`
    elif result == needs_input:
      mark ticket Paused — surface the reason to the user inline
      its dependents stay queued; they will not run until this ticket completes
    elif result == failed:
      same as needs_input — pause it, keep moving
```

**Implementation notes:**
- Use the `Agent` tool with the `general-purpose` subagent type (or a dedicated agent if available) for each `/start` spawn. Pass `run_in_background: true` so they run concurrently.
- Each subagent prompt should start with: "Execute `/start <TICKET-ID>` per the skill. Report `result:` on merge, `needs input:` on any block. Do not engage with anything outside this ticket."
- When notified that a background subagent completes, parse its final message for `result:`, `needs input:`, or `failed:` and act accordingly.
- Never poll. The harness notifies you when a background subagent finishes.

**Verify every subagent's merge claim via `gh` — don't trust the report alone.** The `/start` subagent's final message is meant to end with `result: shipped <TICKET-ID> — PR #<N> merged`, but in practice (per project #2's retro) subagents sometimes return with a review-summary tail instead, and the orchestrator can't tell merged from "almost merged" from the text alone. So after each subagent returns:

1. Extract the branch name (always `westmaas/the-<id>-...` per convention, or pull from Linear ticket's `gitBranchName`).
2. Run `gh pr list --head <branch> --state all --json number,state,mergedAt --limit 1`. Parse:
   - `state: "MERGED"` (and `mergedAt` populated) → confirmed merged. Mark Done, release dependents.
   - `state: "OPEN"` → not merged yet. Treat as **paused** with a note: "<TICKET-ID> subagent returned without merge; PR #<N> still open. Check delivery orchestrator status."
   - `state: "CLOSED"` (and no `mergedAt`) → closed without merge. Treat as **failed** with the PR's close reason.
   - No PR found → treat as **failed** (subagent didn't even push).
3. Independently confirm the Linear ticket's status via `mcp__claude_ai_Linear__get_issue`. If Linear says Done but gh says not-merged (or vice versa), surface the inconsistency to the user and pause that ticket — don't release dependents from a contradictory state.

The verification cost is two cheap reads. The cost of trusting an unverified merge claim is dependents getting unblocked into a broken parent — much harder to recover from.

### 5. Surface progress

Each time the state changes (ticket completes, dependents released, new spawns), emit a one-line status:

```
[project-start] N done / M in-flight / K ready / P paused — released <TICKET-ID> → <TICKET-ID> started
```

Keep this terse. The user is hands-off but should be able to glance.

### 6. Handle pauses and failures

When a ticket pauses or fails:

- Do not retry it automatically.
- Do not start its dependents — they stay queued.
- Continue running everything else.
- The user can address paused tickets out-of-band (answer the question, fix the blocker, re-run `/start <ticket>` manually). When that ticket eventually merges, its dependents become ready again — but you may have already returned. Document this: paused tickets need a manual re-trigger of `/project-start <project>` to resume the queue, or a manual `/start <ticket-id>` on the unblocked dependent.

### 7. On all-done

When `running` and `ready` are both empty and at least one ticket merged:

- If any tickets are paused/failed: stop, do **not** mark project complete. Report `result: project-start halted — N merged, M paused/failed: <list>`.
- If all tickets merged: invoke `/project-retro <project>` to write the summary doc.
- After retro returns: `mcp__claude_ai_Linear__save_project` → status `Completed`, `completedAt` = now.

### 8. Report

Final line on full success: `result: shipped <project-name> — N tickets merged in <duration>`.

On partial: `result: partial — N merged, M paused/failed (see paused list above)`.

## Concurrency caveats

- Default 3 keeps merge-conflict surface low. Override via `concurrency:` in tickets.yaml when planning known parallel-friendly work; lower it for conflict-prone work (e.g., a refactor touching shared infra).
- File-surface auto-sequencing is best-effort — it catches *declared* overlap. If two tickets touch the same file but one didn't declare it, you'll only find out at PR/merge time. Surface this in `/project-retro` so future plans get tighter declarations.

## Two projects in parallel

`/project-start` is safe to run twice for different projects in the same session. Each invocation operates on its own `.handoffs/<slug>/tickets.yaml`, spawns its own subagent pool, and has its own concurrency cap. The only shared risk is two tickets in different projects touching the same file — same as regular concurrent development.

## What this skill does NOT do

- Does not write code or interpret acceptance criteria — that's `/start`'s job.
- Does not edit `tickets.yaml` mid-run. Plan is fixed once execution begins; if you discover the plan was wrong, pause and re-plan.
- Does not force-merge or skip CI on stuck tickets. Pause and report instead.
- Does not delete the handoff bundle on completion. Keep it for retro and future reference.
