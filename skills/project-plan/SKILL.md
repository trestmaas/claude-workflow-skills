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

## Probe the codebase before declaring file surfaces

Before any tickets are written, **probe the repo for its actual conventions** — declared paths that don't match reality cause silent drift at execution time. The probe is cheap; do it once at plan start and refer to it while filling `files:` for each ticket.

Run these globs (adapt to language/framework as needed):

- **Server services:** `src/server/services/**` (or equivalent). Note the actual structure — is it `src/server/services/<group>/<thing>.ts` or flat `src/server/services/<thing>.service.ts`? Across projects #2–#4, server tickets drifted on declared paths every time because the planner assumed dir-grouping that didn't exist. Match the existing convention exactly.
- **Server routers:** `src/server/routers/**` — is there a `viewer` router, an `organizations` router? Procedures land on existing routers when possible.
- **Migrations system:** check for `drizzle/`, `migrations/`, `prisma/migrations/`, or `db/migrate/`. Use the project's actual directory and filename convention (e.g. Drizzle is `drizzle/<NNNN>_<snake>.sql`, not `migrations/<ts>_<snake>.sql`). Migration-path drift is one of the most common errors.
- **UI components:** `src/components/**` or `src/app/**` — observe component-file naming (PascalCase vs kebab), test-file colocation pattern (`Foo.test.tsx` next to `Foo.tsx` vs separate `__tests__/`), and any feature-folder shape.
- **Hooks / contexts:** `src/hooks/**`, `src/contexts/**` — does the project even have these dirs? If not, where do shared hooks land?

When the probe reveals a convention that differs from the typical pattern, **write the actual path in tickets**, not the typical one. Note unusual conventions in the project description's "Background" section so reviewers understand the choices.

If the project doesn't have CLAUDE.md or a clear conventions file, surface the probe results as a brief preamble in `project.md` ("The repo uses flat `*.service.ts` server files; Drizzle migrations at `drizzle/<NNNN>_*.sql`; tests colocated; ...") so the executing subagents can match.

## Up front: assume parallel execution

Everything this skill outputs is in service of `/project-start` running tickets in parallel via background subagents, with no per-ticket babysitting. That means:

- Acceptance criteria must be *testable* and *unambiguous*. Vague criteria → divergent parallel agents.
- Each ticket must declare its **expected file surface** so the orchestrator can auto-sequence tickets that would conflict.
- Each ticket must declare **dependencies** on other tickets in the same project.
- **Plumbing files belong on every sibling ticket that modifies them.** When a scaffolding ticket creates a shared file (wizard shell with a `renderStep()` dispatch, a tabbed layout, a router that sibling tickets each add a route to), every sibling that will touch that file must list it in their `files:`. Otherwise the auto-sequencer doesn't know to serialize them and the orchestrator has to do it by hand mid-run. See "Identify shared plumbing" below.
- **Wiring tickets must reference real surfaces.** If a ticket says "wire X into existing Y," grep for Y at planning time. If it doesn't exist, drop or rescope the ticket. See "Validate wiring tickets" below.

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
    external_depends_on: []          # ticket ids in OTHER projects (cross-project dep)
                                     # /project-start checks these are Done before
                                     # releasing this ticket into ready set
    acceptance:
      - <testable statement>
      - <testable statement>
```

**`external_depends_on`** captures cross-project deps. Example: project #4's UI tickets needed project #3's `THE-256` (admin shell scaffolding) before they could render in the right slot. List the foreign ticket id; `/project-start` will check its Linear status and refuse to release this ticket into the ready set until the external dep is Done. Avoids the situation where an `external_depends_on:` ticket starts but finds half-built foundations.

If a project needs a long-form plan doc (large projects, complex data shapes, tier matrices), also write `docs/plans/<slug>.md` and reference it from both the Linear project description and `project.md`.

## Identify shared plumbing

Before finalizing tickets, look at the scope and ask: **does any ticket create a file that siblings will modify?** Typical patterns:

- **Wizards / multi-step flows** — the shell (`OrgWizardShell.tsx`) routes between steps; each step ticket extends the `renderStep()` switch.
- **Tabbed layouts** — the parent component composes tabs; each tab ticket adds itself.
- **Routers / dispatchers** — the parent maps keys to handlers; each handler ticket registers itself.
- **Shared hooks / contexts** — the provider defines the API surface; consumer tickets extend it.

When you spot this: the **shared file goes on every sibling's `files:` list**, not just the scaffolding ticket's. The auto-sequencer reads file overlap as "serialize these" — that's the correct behavior because two siblings can't safely edit the same file in parallel even with merge auto-rebase.

Example from project #2's first run (THE-247 + step tickets):

```yaml
# Scaffolding ticket creates the shell
- id: THE-247
  files:
    - src/components/orgs/wizard/OrgWizardShell.tsx   # creates
    - src/components/orgs/wizard/StepBasics.tsx       # placeholder
    # ...

# Step tickets each ALSO list the shell
- id: THE-248
  files:
    - src/components/orgs/wizard/StepBasics.tsx       # real impl
    - src/components/orgs/wizard/OrgWizardShell.tsx   # extends renderStep + props
  depends_on: [THE-247]
```

This way THE-248/249/250/251 auto-serialize against each other (all touch `OrgWizardShell.tsx`) instead of racing.

## Validate wiring tickets

A "wiring" ticket is one that says "wire X into existing Y" or "integrate X with current Z" — its scope is to connect new code to surfaces that should already exist.

**Before finalizing such a ticket, grep for the named surface.** If it doesn't exist:

- Either **drop the ticket** (no work to do) and document it in the project description's "Out of scope" section.
- Or **rescope the ticket** to *create* the surface as well, and adjust acceptance criteria accordingly.

Don't ship a wiring ticket on faith. The agent will grep at execution time, find nothing, and silently downgrade the ticket to "shipped the building block" — the wiring never happens. Surface this at plan time, not retro time.

Example: THE-254 was scoped as "wire useInviteAttempt into existing Invite surfaces" but those surfaces don't exist in the codebase. The agent shipped only the hook; the actual wiring is now deferred indefinitely. A planning-time grep would have caught this.

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
