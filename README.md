# claude-workflow-skills

Five Claude Code skills that take you from "idea" to "merged code" with the human in the loop only when it actually matters — pausing on ambiguity, not babysitting each step.

```
/project-plan ──► /project-start ──► /start ──► /ship ──► /project-retro
                  (parallel, hands-off)            (one ticket)    (when project closes)
```

> **Requires the matt-pocock skills.** `/project-plan`, `/start`, and `/ship` delegate their thinking to `/grilling`, `/domain-modeling`, `/tdd`, and `/code-review` rather than duplicating it. Install those alongside this set (run `/setup-matt-pocock-skills`); without them, those `/skill` references dangle.

## What each skill does

| Skill | One-liner |
|---|---|
| **`/project-plan`** | Conversational planner. Asks clarifying questions, then writes a Linear project, per-scope-item tickets, and `.handoffs/<slug>/tickets.yaml` — the machine contract `/project-start` consumes. |
| **`/project-start`** | Reads `tickets.yaml`, builds a DAG (explicit deps + auto-sequenced file conflicts), spawns up to N parallel `/start` background subagents, releases dependents as tickets merge. Pauses individual tickets without halting the whole run. |
| **`/start`** | Single-ticket execution: isolated worktree → Linear In Progress → branch → failing tests against acceptance criteria → implement → `/ship`. Pauses as `needs input:` on ambiguity rather than guessing. |
| **`/ship`** | Take one ticket's local working state to merged: pre-push gate → push → PR → Linear In Review → hand off to a delivery agent → on-merge cleanup. |
| **`/project-retro`** | Post-project writeup with quality signals (CI pass rate, review iterations, reverts, fixups, plan drift). Lives in a Linear doc. No external telemetry. |

## The contract — `tickets.yaml`

The load-bearing artifact. Written by `/project-plan`, read by `/project-start` (and `/start` for cross-checking acceptance), used by `/project-retro` for the plan-vs-actual drift signal.

```yaml
project:
  id: <Linear project id>
  name: <project name>
  slug: <kebab-case-slug>
  phased: false               # true if milestones gate execution
  concurrency: 3              # max parallel /start agents

tickets:
  - id: THE-219
    title: Outcome correlation cron for AI drafts
    milestone: null           # or "Phase 0 — Foundations" for phased projects
    files:                    # expected file surface — used to auto-sequence conflicts
      - src/jobs/outcome-correlation.ts
      - src/jobs/outcome-correlation.test.ts
    depends_on: [THE-217]     # explicit ticket-to-ticket edges
    acceptance:               # testable statements; /start writes failing tests from these
      - "Cron runs daily at 03:00 UTC"
      - "Each ai_generations row gets an outcome_score within 24h of the linked event publish"
```

The novel field is `files:` — declaring expected file surface lets `/project-start` add implicit dependency edges when two tickets would touch the same file, without forcing you to enumerate every conflict by hand.

## Install

```bash
git clone https://github.com/trestmaas/claude-workflow-skills.git
cp -r claude-workflow-skills/skills/* ~/.claude/skills/
```

Reload Claude Code; the five `/` commands appear in your skills list.

## Per-project configuration — `.claude/conventions.yaml`

Drop this in any repo where you want the skills to use that repo's specifics. All fields optional; sensible defaults apply when missing (package-manager auto-detection, common ticket-prefix patterns from recent branches, etc.).

```yaml
linear:
  team: thesignup
  ticket_prefix: THE
  status:
    in_progress: "In Progress"
    in_review: "In Review"
    done: "Done"

branch:
  # Variables: {prefix} (THE), {prefix_lower} (the), {id} (numeric), {slug}
  format: "westmaas/the-{id}-{slug}"

gate:
  - bun run lint
  - bun run typecheck
  - bun run test:run
  - bun run build

test:
  command: "bun run test:run"
  bail: "bun run test:run --bail"

delivery:
  agent: code-delivery-orchestrator
```

See [`examples/conventions.yaml`](examples/conventions.yaml).

## Requirements

- **Linear MCP** for ticket and project operations (`mcp__claude_ai_Linear__*` tools).
- **`gh` CLI** authenticated to your GitHub repo.
- **Git worktree support** (built into modern git). `/start` uses `EnterWorktree` for parallel isolation.

Optional but recommended:
- A delivery subagent (e.g. `code-delivery-orchestrator`) that runs `/review`, `/security-review`, watches CI, and merges. If absent, `/ship` inlines those steps.

## Design notes

- **Hands-off, not autonomous.** Skills pause as `needs input:` whenever they hit ambiguity. Better to stop and ask than silently divergent parallel agents.
- **One worktree per ticket** during parallel execution — keeps subagents from stomping each other's files.
- **`.handoffs/<slug>/` is persistent**, not ephemeral. It's the plan as a file. `/project-retro` diffs it against what actually shipped.
- **Telemetry stays local.** Quality signals come from git + gh + Linear. No external pipeline by default. Add one only when a pattern starts mattering longitudinally.

## License

MIT (see [LICENSE](LICENSE)).
