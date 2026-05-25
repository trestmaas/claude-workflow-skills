---
name: project-plan
description: Turn an idea into a well-structured Linear project ready for hands-off parallel execution. Conversational — asks clarifying questions before scaffolding. Outputs a Linear project, per-scope-item tickets, and `.handoffs/<slug>/tickets.yaml` — the machine contract /project-start consumes (with file surface and per-ticket dependencies). Reads `.claude/conventions.yaml` for Linear team / ticket-prefix conventions.
---

# /project-plan

Turn a one-line idea into a Linear project sized for hands-off parallel execution.

## Conventions

```yaml
linear:
  team: thesignup            # Linear team name to file tickets under
  ticket_prefix: THE         # Used in display; Linear assigns the actual id.
```

If unset, ask which Linear team to use (`mcp__claude_ai_Linear__list_teams`).

## When to use

- Starting any non-trivial body of work (roughly 5+ tickets).
- Scaffolding a follow-up to a project that just shipped.
- Batch-creating several projects in planning state — run `/project-plan` multiple times; projects sit in Backlog until `/project-start` fires them.

For one-off tickets, skip this and use `/start` directly.

## Up front: assume parallel execution

Everything this skill outputs is in service of `/project-start` running tickets in parallel via background subagents, with no per-ticket babysitting. That means:

- Acceptance criteria must be *testable* and *unambiguous*. Vague criteria → divergent parallel agents.
- Each ticket must declare its **expected file surface** so the orchestrator can auto-sequence tickets that would conflict.
- Each ticket must declare **dependencies** on other tickets in the same project.

## Conversation flow

Ask these one or two at a time, not all at once. After each answer, write the answer back in your own words and ask the next.

1. **What are we building and why now?** (frames the Why / Background)
2. **What does "done" look like?** (frames the Goal — one crisp sentence)
3. **What's explicitly out of scope?** (forces the boundary — vague boundaries kill parallel execution)
4. **Depends on / unblocks any other projects?** (project-level DAG)
5. **Rough cardinality?** small (~5 tickets), medium (~12), large (20+).
6. **Phased or flat?** — phased means a milestone gate matters (e.g., "Phase 0 — Foundations" must complete before Phase 1). Flat means tickets can fire in any order subject to per-ticket deps. Default to flat unless you hear a clear sequencing reason.
7. **Follow-up to a prior project?** — if yes, fetch the parent via `mcp__claude_ai_Linear__get_project` and thread its context (PRs merged, deferred work) into the new Why.

## Output: three artifacts

### 1. Linear project (Backlog state)

Create via `mcp__claude_ai_Linear__save_project`. Use this section structure in the description:

```markdown
## Why / Background
<narrative — what existed before, what changed, why now. Thread prior PRs/projects if relevant.>

## Goal
<one sentence>

## Scope
1. <item>
2. <item>
...

## Out of scope
- <item>
- <item>

## Depends on / unblocks
- Depends on: <project link>
- Unblocks: <project link>

## Plan doc
See `docs/plans/<slug>.md` (large projects only — skip for small/medium)

## Handoff bundle
`.handoffs/<slug>/`
```

Set milestones only for **phased** projects. Name them `Phase 0 — <name>`, `Phase 1 — <name>`, etc. Each milestone gets a one-line description.

### 2. Per-scope-item Linear tickets

Create one ticket per scope item via `mcp__claude_ai_Linear__save_issue`. Use the configured `linear.team`. Each ticket gets:

```markdown
## Acceptance criteria
- <testable statement — something a test or a human can falsify>
- <testable statement>
- <testable statement>

## Expected file surface
- src/foo/bar.ts
- src/foo/bar.test.ts
- e2e/specs/foo.spec.ts

## Depends on
- <TICKET-ID> (sibling ticket in this project), if any
```

Set priority and assign to the project. Initial status: `Backlog` (will move to `Todo` when `/project-start` fires).

### 3. `.handoffs/<project-slug>/` bundle

This is the machine-readable contract `/project-start` consumes. Layout:

```
.handoffs/<project-slug>/
├── project.md       # full plan, same content as Linear project description
└── tickets.yaml     # the contract
```

`tickets.yaml` format — this is load-bearing, don't deviate:

```yaml
project:
  id: <Linear project id or slug>
  name: <project name>
  slug: <kebab-case-slug>
  phased: false                      # true if milestones matter
  concurrency: 3                     # default; override per-project if conflict-prone

tickets:
  - id: <TICKET-ID>                  # filled in after Linear save
    title: <ticket title>
    milestone: null                  # or "Phase 0 — Foundations" for phased projects
    files:                           # expected file surface (paths or globs)
      - src/auth/middleware.ts
      - src/auth/middleware.test.ts
    depends_on: []                   # other ticket ids in this project
    acceptance:
      - <testable statement>
      - <testable statement>
```

If a project needs a long-form plan doc (large projects, complex data shapes, tier matrices), also write `docs/plans/<slug>.md` and reference it from both the Linear project description and `project.md`.

## Asking-questions discipline

- Don't ask all 7 questions at once. Ask 1–2, listen, restate, ask the next.
- If the user gives a tight one-liner upfront ("scaffold a follow-up to <Project> covering the deferred polish") you can skip directly to confirming and proceed.
- If the user pushes back on a scope item ("nah, drop #3"), update the plan and proceed — don't relitigate.
- Push back when you see a vague acceptance criterion. "Make it better" or "polish the UI" are not testable — ask for a concrete check.

## What this skill does NOT do

- Does not implement anything. No code is written.
- Does not start execution. The project sits in Backlog until you run `/project-start <project>`.
- Does not create a branch or worktree.
- Does not invent dependencies between tickets you didn't mention. If the file surface implies a conflict but you didn't declare a dependency, *ask* — don't silently add one.

## Report

Final line: `result: planned <project-name> — N tickets, M depends_on edges, handoff at .handoffs/<slug>/`.
