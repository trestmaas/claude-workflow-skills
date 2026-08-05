---
name: project-start
description: Execute a planned project hands-off in parallel. Reads `.handoffs/<slug>/tickets.yaml`, builds a DAG from explicit depends_on edges plus auto-sequenced file-surface conflicts, then spawns up to N (default 3) background /start agents — releasing dependents as tickets merge. Pauses individual tickets as needs input without halting others. On all-done, calls /project-retro.
---

# /project-start

Take a project that's been `/project-plan`ned and execute it end-to-end, parallel, hands-off.

## Preconditions

- **Spawn every child with `isolation: "worktree"`.** This is the single most important line in the skill. Pass `isolation: "worktree"` on every `Agent` call. The child is then already in its own harness-provided worktree — its `/start` prompt must tell it **not** to call `EnterWorktree`, and just to work in its cwd.
  - Why, and read this before "fixing" it: children **cannot** self-isolate. `EnterWorktree` refuses from a subagent with a cwd override ("it would mutate the parent session's process-wide working directory"), and the manual `git worktree add` fallback gets its first `Write` **rejected** by the bg-isolation guard, which is not path-scoped — it blocks the child's writes wholesale whenever the *parent* session is sitting on the shared checkout. Both remedies the guard names (`isolation: "worktree"`, or the parent isolating) are things only the **caller** can do.
  - The old advice here — "must NOT run from inside a worktree, so children can self-isolate" — was **exactly backwards** and cost two full agent lifecycles on the multi-calendar project before it was diagnosed. Exiting the worktree is what *causes* the children's writes to be blocked. Do not restore it.
  - The `pwd`-not-in-`.claude/worktrees/` check still holds, but for a different reason: `/project-start` should orchestrate from the main checkout so `.handoffs/` and `main` resolve normally. If `main` is checked out in another worktree, don't switch the user's branch — read the bundle from `origin/main` with `git show origin/main:.handoffs/<slug>/tickets.yaml`. Children branch from `origin/main` regardless.
- A `.handoffs/<project-slug>/tickets.yaml` exists. If not: pause `needs input: no handoff bundle for <project>, run /project-plan first`.
- The Linear project is in `Backlog` or `Planned`. If it's already `In Progress`, ask whether to resume or restart.
- **The evergreen "Manual tasks" project is never an execution target.** It has no handoff bundle, its tickets have no file surface, and it is permanently `In Progress` by design. If asked to run it, refuse and point at `/manual-tasks`. Never mark it Completed — step 7.4 does not apply to it.

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

### 1b. Refuse to spawn tickets carrying unresolved acceptance criteria

Scan each eligible ticket's acceptance criteria — in `tickets.yaml` **and** on the Linear ticket — for unresolved-decision markers: `OPEN`, `TBD`, `needs a call`, `decide before build`, `do not guess`, `RESOLVE FIRST`.

A ticket carrying one of these **will** pause the instant its `/start` agent reads it. Spawning it burns a full agent lifecycle, a worktree, and a human round-trip to learn what you already knew at DAG-build time.

Surface them all up front instead, and let the human clear them in one pass:

```
needs input: N ticket(s) have unresolved acceptance criteria — resolve before I spawn them:
  - <TICKET-ID>: <the open question>
  - <TICKET-ID>: <the open question>
```

Evidence from the Public org events catalog run: SIGN-340 and SIGN-342 each paused mid-flight on an unresolvable criterion. SIGN-344 *also* carried an open question — but it was traced and resolved **before** spawning, and it shipped without pausing. Same class of ticket, two very different costs. Resolve first, spawn second.

### 2. Build the DAG

For each ticket:

- **Explicit edges:** every entry in `depends_on` is a hard edge (same-project).
- **External edges:** every entry in `external_depends_on` is a hard edge against a ticket in *another* Linear project. These behave like `depends_on` but resolve via Linear status (the external ticket must be in a Done-type state). Check via `mcp__claude_ai_Linear__get_issue` once at DAG-build time; cache the result. If any `external_depends_on` ticket is not Done, the dependent ticket starts in the **external-blocked** set, not the ready set — it stays blocked until the external dep moves to Done (the orchestrator re-polls these at each completion-checkpoint, since the external project might be running in parallel and shipping while this one runs).
- **Implicit edges (auto-sequenced):** if ticket A and ticket B both list overlapping paths in `files` and neither depends on the other, add the implicit edge `B depends_on A` (or vice versa — pick the one with lower ticket-id number for determinism). Log the auto-sequence to the user so they can override.
- Detect cycles. If a cycle exists, pause `needs input: dependency cycle detected: <cycle>`.

Compute the ready set: tickets with no unresolved dependencies (internal or external).

If the initial ready set is empty AND tickets exist in the external-blocked set, surface this: `needs input: nothing ready to run — N tickets blocked on external deps: <list of {ticket → external dep status}>. Resolve those before resuming.`

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
- Each subagent prompt should start with an **imperative that forces action, not restatement**: "Begin now by invoking `/start <TICKET-ID>`. This is a real work assignment — actually execute it, don't restate it. Your first action should be a Bash call." One participant-flow-repair spawn opened with "Execute `/start …`", consumed its own setup reminder as if it were the task, replied "the user wants me to invoke /start", and exited with **0 tool uses** — a dud launch that looks completed but did nothing. Verify a fresh spawn actually started (it reported In Progress / pushed a branch); a return with near-zero tool use is a dud — re-spawn it.
- **Make the `/start` prompt include a worktree self-check as its first action:** "Run `git rev-parse --show-toplevel`; if it is not under `.claude/worktrees/`, you are NOT isolated — create a real worktree per the /start fallback and use `git -C`, never mutate the shared checkout's HEAD." `isolation: "worktree"` occasionally fails silently — one agent ran in the shared main checkout and its `git checkout -b` moved the shared HEAD before it detected and recovered. The self-check catches it.
- **Tell every `/start` prompt to `git fetch` and branch from the fetched `origin/main`, and to stop-and-report if a premise is already fixed** (a valued outcome, not a failure). This is the execution-time half of the planner's fetch-first rule and it is what catches a stale plan before it ships wrong code.
- When notified that a background subagent completes, parse its final message for `result:`, `needs input:`, or `failed:` and act accordingly.
- Never poll. The harness notifies you when a background subagent finishes.

**Verify every subagent's merge claim via `gh` — don't trust the report alone. This is mandatory, not belt-and-suspenders.** The `/start` subagent's final message is meant to end with `result: shipped <TICKET-ID> — PR #<N> merged`, but in practice subagents return without merging, without reviewing, or without knowing they failed. The orchestrator can't tell merged from "almost merged" from the text alone. So after each subagent returns:

1. Extract the branch name (per the configured `branch.format` from `.claude/conventions.yaml`, or pull from Linear ticket's `gitBranchName`).
2. Run `gh pr list --head <branch> --state all --json number,state,mergedAt --limit 1`. Parse:
   - `state: "MERGED"` (and `mergedAt` populated) → confirmed merged. Mark Done, release dependents.
   - `state: "OPEN"` → **belt-and-suspenders auto-merge — but only if the subagent reported `result:` (merge intended, delivery fumbled).** Run `gh pr merge <N> --auto --squash` defensively (retry once with 2s backoff on the transient `enablePullRequestAutoMerge` GraphQL error). Then wait briefly (~10s) and re-check state. If now MERGED → mark Done. If still OPEN → **pause** with note "<TICKET-ID> subagent returned without merge; PR #<N> still open. Auto-merge queued; check CI."

     **Never defensively arm a PR whose subagent returned `needs input:` or `failed:`.** As of the `/ship` fix, auto-merge is armed *after* reviews return clean — so an un-armed open PR may mean the reviews found something, not that the agent forgot. Arming it here would merge exactly the code a reviewer just objected to, and it would look like a recovery. If the subagent paused, leave the PR open and keep it paused. The whole point of moving auto-merge behind the reviews is lost if the orchestrator arms it anyway.
   - `state: "CLOSED"` (and no `mergedAt`) → closed without merge. Treat as **failed** with the PR's close reason.
   - No PR found → treat as **failed** (subagent didn't even push).
3. Independently confirm the Linear ticket's status via `mcp__claude_ai_Linear__get_issue`. If Linear says Done but gh says not-merged (or vice versa), surface the inconsistency to the user and pause that ticket — don't release dependents from a contradictory state.

The verification cost is two cheap reads + one defensive merge call. The cost of trusting an unverified merge claim is dependents getting unblocked into a broken parent — much harder to recover from. Across projects #2 and #3, 5 of 21 subagent returns required this fallback — about 25%. Not optional.

### The green-but-open stall — nudge the owner, don't bare-merge

The single most common delivery failure on participant-flow-repair (it hit most tickets) was not a crash: the `/start` agent pushed, handed off, set its *own* background CI monitor, and went **idle** — CI then went fully green and the PR sat OPEN forever because the monitor exited without waking the agent. The agent never returns a `needs input:`; it just reports "waiting on CI" and stops. Nothing in the DAG moves.

**Treat "agent returns without a `result:` line" as the EXPECTED path, not an anomaly — and do not try to instruct it away.** On "Monetize the AI creation flow", 3 of 10 agents pushed a PR and ended their turn *without arming auto-merge*, and a 4th armed then idled re-reporting CI. One of the three was told **explicitly, in its spawn prompt**, not to stall — and stalled at exactly the same point anyway. The stall is structural: the agent's turn ends right after it emits the review, which is the step just before arming. Prompt wording does not fix it. The orchestrator-side watch + resume is the *only* mitigation that has ever worked. So budget for it: every ticket's normal lifecycle is "subagent returns having done the work but not closed delivery → orchestrator verifies via `gh` → orchestrator resumes the owning agent (or, under the review gate above, runs the independent review and then arms). Do not read a missing `result:` as failure; read it as the handoff point where the orchestrator takes over.

Two defenses, used together:
- **Arm your own per-PR merge/stall monitor as the default, not a fallback — and arm it the moment the PR exists, not when the agent tells you about it.** Run a background `Monitor` that polls the PR and emits on exactly three terminal states: `MERGED`, `CI-FAILED`, and **`GREEN-but-still-OPEN`**. The third is the stall signal, and only an orchestrator-level watch reliably catches it — the agents' own monitors don't.

  This used to say "after a subagent reports its PR is up-and-in-CI." That waits on a signal that frequently never arrives cleanly. **Across three consecutive projects, 7 of 7 `/start` agents ended their turns idle-waiting on CI rather than confirming a merge** — several pinged "waiting on build" four or five times without ever reporting terminal state. Do not gate your watch on their report. Poll `gh pr list --head <branch>` yourself once a branch is pushed, and arm the monitor as soon as a PR number exists.

  Concretely, a monitor covering several PRs at once works well and costs one tool call:

  ```bash
  declare -A fin
  while true; do
    for p in <pr numbers>; do
      [ -n "${fin[$p]}" ] && continue
      st=$(gh pr view $p --json state --jq '.state' 2>/dev/null) || continue
      [ "$st" = "MERGED" ] && { echo "PR #$p MERGED"; fin[$p]=1; continue; }
      [ "$st" = "CLOSED" ] && { echo "PR #$p CLOSED without merge"; fin[$p]=1; continue; }
      f=$(gh pr checks $p --json name,state 2>/dev/null | jq -r '[.[]|select(.state=="FAILURE" or .state=="ERROR")]|length' 2>/dev/null || echo 0)
      [ "${f:-0}" -gt 0 ] && { echo "PR #$p CI FAILED"; fin[$p]=1; }
    done
    # ...break when all terminal
    sleep 30
  done
  ```

  Evidence this is load-bearing, not belt-and-suspenders: on the Behavioral/Calendar runs the orchestrator monitor caught **every** merge, and caught the one PR that was genuinely stranded (#651 — all checks green, auto-merge never armed, would have sat open indefinitely). Without it nothing in the DAG would have moved.

  **But the `Monitor`-tool watch has itself been observed to go silent — treat it as best-effort, not the authoritative merge-detector.** On the Event-cover-images run, two persistent `Monitor`s over merged PRs never emitted, and the orchestrator idled **~7h between waves** until a human "stuck?" nudge; every merge had actually landed and been findable by a plain `gh pr view`. The reliable primitive is a **bounded `Bash run_in_background` until-loop that exits when all watched PRs are terminal** (one guaranteed completion notification), plus a `gh pr view` on each armed PR at every agent-completion checkpoint. Make the bounded waiter the primary merge-detector; the `Monitor` is at most a redundant tap.

  ```bash
  # bounded waiter — one guaranteed notification when all PRs go terminal
  for i in $(seq 1 80); do            # 80 * 30s = 40min cap
    done=1
    for p in <pr numbers>; do
      st=$(gh pr view $p --json state --jq '.state' 2>/dev/null || echo '?')
      case "$st" in MERGED|CLOSED) ;; *) done=0;; esac
    done
    [ "$done" = 1 ] && { echo "all terminal"; exit 0; }
    sleep 30
  done
  echo "TIMEOUT — some PRs still open"
  ```
- **On a green-but-open stall, resume the *owning* agent (`SendMessage`), don't merge it yourself bare.** The owning agent holds the review record; a message resumes it from its transcript and it completes review-confirmation + merge in one step. A bare `gh pr merge` from the orchestrator is correctly **blocked** when the PR has no documented review (see below) — and it should be. Reserve the orchestrator's own merge for when you have *first* produced the review record (e.g. via a dedicated review-then-merge agent), which is the right recovery when the owning agent is truly dead rather than merely idle.

**Do not merge a PR on CI-green alone.** A green build is not a passed review. If a subagent's delivery stalled such that `/code-review` + `/security-review` never completed (common when the *delivery* sub-agent dies, e.g. during an infra outage), the PR has green CI and **no review record** — merging it there skips the one gate every other PR passed. The host may block the bare merge; that block is correct. Route it through an agent that runs the reviews scoped to `origin/main...<branch>` first, then merges.

### The delivery hand-off is untrusted by default

Mobile-responsive-fixes ran 15 tickets through the delivery agent. It failed in **five distinct ways**, and every failure was caught only by checking `gh`/Linear directly rather than believing the report:

1. **Returned without producing `/code-review` or `/security-review` output** (×3) — "it ran" is not "it passed."
2. **Died mid-response** on an API error, after queueing the merge but before reporting.
3. **Stopped before arming auto-merge.** PR #528 sat OPEN with green CI and would have waited forever. Nothing in the DAG would have moved.
4. **Let Linear drift out of sync** with a merged PR (×3) — tickets stuck in `In Review` while their code was on `main`. Closeout would have refused to complete the project.
5. **Reviewed a stale merge-base** — diffed 168 files instead of 9, so its "review" never looked at the PR's actual code at all.

Failure modes 3 and 5 are the dangerous ones: a silently stranded PR blocks the whole DAG, and a review of the wrong diff is worse than no review because it *reads* like assurance. (In this run, mode 5 nearly let a runtime no-op ship — the `/start` agent discarded the bogus review and re-ran it correctly.)

So, for every ticket, the orchestrator does all three of these — no exceptions, no "the agent said it was fine":

- **Auto-merge armed?** `gh pr view <N> --json autoMergeRequest`. If null and the PR is open, arm it yourself. A subagent's "done" does not imply a queued merge.
- **Linear matches GitHub?** `mcp__claude_ai_Linear__get_issue` vs `gh pr view --json state`. Reconcile drift to whatever GitHub says — the merge is the ground truth, the ticket status is bookkeeping.
- **Review artifacts exist and targeted the right diff?** If the hand-off came back without them, or its diff doesn't match `gh pr diff <N> --name-only`, treat the review as **not done** and re-run it scoped explicitly to `origin/main...<branch>`.

Also brief every `/start` subagent that the delivery agent is unreliable, so it doesn't accept an empty hand-off either. In this run the subagents caught most of these themselves once told to expect them — the defense works best at both layers.

### Gate every PR on an INDEPENDENT review before arming the merge — the orchestrator is the only layer that can do this

A `/start` subagent has **no sub-agent tool**. So when a project configures `delivery.agent` (e.g. `code-delivery-orchestrator`), that agent frequently *cannot be spawned at all* from inside the subagent — the subagent silently falls back to reviewing **its own diff inline**. Self-review is structurally weaker than independent review: an author checking their own code shares the author's blind spots, and will confirm the very property they're violating.

This is not hypothetical. On the "Monetize the AI creation flow" project, the delivery agent was **never once spawnable** across 10 tickets; every ticket self-reviewed. Independent review was then applied to 3 of the 10 PRs and found a **BLOCKING defect in all 3** — an untagged share URL that violated the repo's mandatory UTM convention (unrecoverable attribution loss), a counter that painted a stale value because the *test's* mock was synchronous where real react-query is not, and an e2e guard that was inert because its waiter was satisfied six UI steps too early. Self-review found **zero** blocking defects across all 10. In each case the author had explicitly reasoned about the property being violated. **A 3/3 hit rate on the reviewed subset means the unreviewed PRs should be assumed to carry comparable defects.**

The orchestrator *does* hold the Agent tool. So the orchestrator — not the subagent — spawns the independent reviewer, and gates the merge on it:

1. When a `/start` subagent reports its PR is up with the gate green, do **not** let it arm auto-merge as the final step. Instruct subagents (in their spawn prompt) to push, open the PR, run the gate, set Linear In Review, and **stop without arming** — then report the PR number.
2. Spawn a **fresh** `general-purpose` agent (NOT `run_in_background`-coupled to the author; a clean context that did not write the code) as a read-only reviewer: "you did not write this, find what its author missed." Point it at the PR's actual risk surface and tell it to distinguish BLOCKING from "I'd have done it differently." Have it end with a single `VERDICT:` line.
3. **Verify the fix, don't trust the report.** If the reviewer finds a blocking defect, `SendMessage` the *owning* agent with the finding; when it reports fixed, read the diff yourself before arming.
4. Only arm auto-merge (`gh pr merge <N> --auto --squash`) once the independent review is clean **or** its findings are fixed and verified. This deliberately serializes review before merge instead of merging-then-reviewing.

Cost: one extra agent per ticket. Benefit, measured: three defects that would otherwise have shipped, one of them permanently unrecoverable. When `delivery.agent` is unspawnable this is the *only* independent check in the pipeline — treat it as mandatory, not belt-and-suspenders. If a run already merged PRs without this gate (e.g. because the DAG raced ahead), retro-review those merged PRs adversarially at closeout and file any findings as follow-up tickets — a merged defect is a ticket, not a lost cause.

**Repo note — thesignup:** its configured `code-delivery-orchestrator` (`delivery.agent`) has **never** been spawnable from inside a `/start` subagent across multiple projects, so on this repo the orchestrator-spawned independent reviewer is *always* the only gate — never skip it. The gate has earned it: on the Event-cover-images run 2 of 6 PRs carried a BLOCKING defect that self-review missed and CI was green over (a cross-tenant blob-delete IDOR, and a draft cover leaking via og:image), both caught and fixed pre-merge.

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

### 7. On all-done (closeout)

When `running` and `ready` are both empty and at least one ticket merged, run the closeout in order:

**7.1 Reconcile Linear with reality.** For each ticket in the project:

- Fetch current Linear status via `mcp__claude_ai_Linear__get_issue`.
- If status is already in a Done-type state (`Done`, `Completed`, `Canceled`), skip.
- Otherwise: extract the branch name (per `branch.format` or Linear's `gitBranchName`) and run `gh pr list --head <branch> --state all --json number,state,mergedAt --limit 1`.
  - If a PR exists with `state: "MERGED"`: **update Linear to Done** via `mcp__claude_ai_Linear__save_issue` and post a comment: "Auto-reconciled by `/project-start` closeout — PR #<N> was merged but Linear status was `<prior-status>`. Likely the `/start` subagent's final Linear update missed."
  - If a PR exists with `state: "OPEN"`: run the defensive `gh pr merge <N> --auto --squash` (with the GraphQL-flake retry). Wait ~10s, re-check. If now MERGED, update Linear to Done as above. If still OPEN, leave as-is — the pause/fail check below will catch it.
  - If `state: "CLOSED"` (no merge) or no PR: leave as-is.

This step is the safety net for the common drift pattern: `/start` subagent's PR auto-merges via GitHub but its final Linear-status update failed or was skipped. Without this, the orchestrator would falsely classify the ticket as paused and refuse to complete the project.

**On thesignup this is the rule, not the exception.** The GitHub→Linear integration does **not** auto-advance a ticket on squash-merge here — on the Event-cover-images run all 6 tickets sat in `In Review` after their PRs merged and every one had to be reconciled to Done. Budget for reconciling *every* ticket each run on this repo, and don't read the universal `In Review` state as "nothing merged."

**7.2 Pause/fail gate.** Re-count tickets after reconciliation:

- If any tickets are still NOT in a Done-type state: stop, do **not** mark project complete. Report `result: project-start halted — N merged, M paused/failed: <list>`.
- If all tickets are Done: continue.

**7.3 Retro.** Invoke `/project-retro <project>` to write the summary doc.

**7.4 Mark project Completed — explicit, verified, unmissable.**

This is the most-skipped step in practice (projects #2 and #4 of the Org UX initiative both ran to all-tickets-Done but stayed In Progress in Linear because 7.4 didn't fire). Do not treat it as a side-effect of 7.3. Run it as its own distinct action:

1. Call `mcp__claude_ai_Linear__save_project` with `state: "Completed"`.
2. **Verify.** Call `mcp__claude_ai_Linear__get_project` with the project id and assert `status.name == "Completed"`. If not, retry the save once; if still not, surface explicitly: `needs input: project save_project succeeded but get_project shows status <X> — Linear may have a workflow-state rule blocking the transition; flip manually and investigate.`
3. Emit the status line: `[project-start] project <slug> → Completed`.

If the orchestrator skips this step for any reason (early return, exception in retro, mistake), the project state is wrong everywhere downstream (the initiative rollup, dashboards, future `/project-plan` "depends on" lookups). Make the call, then prove it landed.

### 7a. Surface retro recommendations as a `needs input:` pause

After `/project-retro` writes the doc and the project is marked Completed, **read the retro back via `mcp__claude_ai_Linear__get_document`** and look for the "Recommendations for next time" section.

For each recommendation, draft a one-line proposed patch (which skill file, what change). Then emit a `needs input:` with this format:

```
needs input: project shipped. Retro at <doc URL>.

N recommendations to apply to the workflow-skills:

1. <recommendation summary> — proposed: <one-line patch description> in <skill file>
2. ...

Reply "all", "none", a list (e.g. "1, 3"), or any free-text edits.
```

This is the deliberate notification trigger so the human can decide whether to harden the skills based on real-run signal. The whole loop becomes self-improving: each project run produces both shipped code *and* a concrete proposal for what to change in the orchestrator.

If the retro has no recommendations (clean run, no learnings), skip this step and just report.

### 7b. Surface the manual tasks this run opened

Before reporting, query open issues labelled `manual` created since the project's `startedAt`. These are the human-only prerequisites the run uncovered — env vars, DNS, dashboard config — that were deliberately *not* allowed to block any merge.

List them in the report, Urgent ones first:

```
manual: K task(s) opened this run — <ID>: <one line> [blocks: SIGN-xxx is inert until done]
```

**A project can be 100% merged and still not work.** That is the normal, expected outcome of the manual-task channel doing its job, not a failure — but it has to be *said*, in the same message that announces the merges, or it isn't said anywhere the user will read. Do not let a clean `result:` line be the only thing they see.

Do not block completion on these and do not attempt them yourself — `/manual-tasks` is where they get worked.

### 8. Report

Final line on full success: `result: shipped <project-name> — N tickets merged in <duration>`.

On partial: `result: partial — N merged, M paused/failed (see paused list above)`.

## Concurrency caveats

- Default 3 keeps merge-conflict surface low. Override via `concurrency:` in tickets.yaml when planning known parallel-friendly work; lower it for conflict-prone work (e.g., a refactor touching shared infra).
- File-surface auto-sequencing is best-effort — it catches *declared* overlap. If two tickets touch the same file but one didn't declare it, you'll only find out at PR/merge time. Surface this in `/project-retro` so future plans get tighter declarations.
- **Serialize on edit *regions*, not filenames — git auto-merges disjoint hunks.** The auto-sequencer serializes any two tickets sharing a file, which is the safe default. But when several ready tickets all list one hotspot file (an `EventManagement.tsx`, a barrel, a router), check whether their actual edits fall in *disjoint regions* before forcing them serial. On P3, four tickets "touched `EventManagement.tsx`" — but three edited provably non-overlapping regions (a header count / a deleted `<section>` + import / one prop line ~50 lines apart), and git rebase auto-merges non-overlapping hunks cleanly. Running them concurrently merged with zero conflicts; serializing would have cost three cycles to prevent a conflict that can't happen. The one that genuinely *restructured* the file (the toolbar hoist) did have to land first. Rule: overlap of *regions* forces serial; shared filename with disjoint regions does not. Grep each ticket's target lines/symbols to decide; if you can't prove disjointness, serialize.
- **A CI-*failed* check on a long-armed PR is usually a stale branch, not a code defect.** Distinct from the green-but-open stall above: a PR that armed auto-merge early, then sat while N siblings merged under it, can go red on a *required* check purely because its branch is now behind `main` — a dep lockfile bump (agents reinstalling `node_modules` mid-run shift `@types/*` versions), a renamed symbol, or a type a sibling changed. CI builds the branch-merged-with-`main`, so it fails even though the PR passed its own gate locally. On P3, SIGN-426 sat armed-but-blocked for ~2h on a `Typecheck` failure that was one stale mock-call type against the new `@types/bun`. **Before treating a long-armed red PR as a real failure: rebase it onto `origin/main` in a worktree and re-run just the failing check.** If it's a clean rebase + a mechanical fix (a cast, an import, a renamed reference), the orchestrator can own that fix directly (same class as arming a merge — it is not writing feature code), force-push, and re-arm. Only if the rebase conflicts or the failure is substantive do you route it back to an agent.

## Two projects in parallel

`/project-start` is safe to run twice for different projects in the same session. Each invocation operates on its own `.handoffs/<slug>/tickets.yaml`, spawns its own subagent pool, and has its own concurrency cap. The only shared risk is two tickets in different projects touching the same file — same as regular concurrent development.

## What this skill does NOT do

- Does not write code or interpret acceptance criteria — that's `/start`'s job.
- Does not edit `tickets.yaml` mid-run. Plan is fixed once execution begins; if you discover the plan was wrong, pause and re-plan.
- Does not force-merge or skip CI on stuck tickets. Pause and report instead.
- Does not delete the handoff bundle on completion. Keep it for retro and future reference.
