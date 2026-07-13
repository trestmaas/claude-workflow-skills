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
- **Test-file naming — probe the RUNNER's globs, not just where tests live.** Read the test scripts in `package.json` and the runner configs (`vitest.config.*`, `playwright.config.*`, `bunfig.toml`) and note **which glob picks up which directory**. A repo can have two runners splitting the same tree by filename suffix. On the multi-calendar project two tickets drifted because `test:bun` only globs `*.bun.test.ts` in `src/lib/calendar/` and `src/components/**` — a plainly-named `foo.test.ts` there would have silently fallen through to vitest and run under the wrong environment. The plan declared `googleEvents.test.ts`; the real file had to be `googleEvents.bun.test.ts`. Looking at *where* tests live told us nothing; only the runner's glob did. Declare the filename the runner will actually pick up.
- **Hooks / contexts:** `src/hooks/**`, `src/contexts/**` — does the project even have these dirs? If not, where do shared hooks land?
- **Route gating (layouts / middleware):** for any route you're adding — and *especially* any route meant to be **public** — enumerate what already **wraps** it: `layout.tsx` files up the segment tree, `middleware.ts` matchers, parent-level session/membership checks. A file surface that lists only what you'll *write* misses what will *wrap* it. On the Public org events catalog project, SIGN-341's "page is NOT member-gated" AC was silently unsatisfiable because `/o/[slug]/layout.tsx` enforced auth + org membership across the whole segment — and that file appeared in **no ticket's declared file surface**. The agent only found it by tracing at build time; a planning-time probe would have caught it.

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

Run the clarify step as a `/grilling` interview, not a flat questionnaire — the 7 questions below are its agenda, not its ceiling. Grilling pushes on vague answers, surfaces the assumption behind each one, and won't let a fuzzy boundary survive; that rigor is exactly what parallel execution needs (vague criteria → divergent agents). Use the questions to make sure grilling covers the planning-specific ground (cardinality, phasing, DAG), then fold what it extracts into the artifacts below.

Ask these one or two at a time, not all at once. After each answer, write the answer back in your own words and ask the next.

1. **What are we building and why now?** (frames the Why / Background)
2. **What does "done" look like?** (frames the Goal — one crisp sentence)
3. **What's explicitly out of scope?** (forces the boundary — vague boundaries kill parallel execution)
4. **Depends on / unblocks any other projects?** (project-level DAG)
5. **Rough cardinality?** small (~5 tickets), medium (~12), large (20+).
6. **Phased or flat?** — phased means a milestone gate matters (e.g., "Phase 0 — Foundations" must complete before Phase 1). Flat means tickets can fire in any order subject to per-ticket deps. Default to flat unless you hear a clear sequencing reason.
7. **Follow-up to a prior project?** — if yes, fetch the parent via `mcp__claude_ai_Linear__get_project` and thread its context (PRs merged, deferred work) into the new Why.

## Pin the vocabulary before writing tickets

The interview will surface domain terms — some fuzzy, some overloaded (one word doing three jobs). Before writing acceptance criteria, run `/domain-modeling` to sharpen those terms and record them in `CONTEXT.md` (create it if absent). Then **write ticket titles and acceptance criteria in that pinned vocabulary**, and note in `project.md` that executing subagents should read `CONTEXT.md` for the glossary. Consistent language across tickets is what keeps N parallel agents from each naming the same concept differently — the vocabulary equivalent of the shared-plumbing rule below.

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

## Integration ticket for composition-heavy projects

When a project produces multiple component blocks that all mount into one parent (sidebar with sections, dashboard with cards, tab bar with tabs, layout with slot children), the per-block tickets are not enough on their own — each block can ship to disk without ever being composed into the parent.

This is the "components shipped but never composed" failure mode. Post-Org-UX-initiative, the admin shell sidebar shipped THE-258 (org switcher) and THE-259 (role-gated bottom band) as separate components with correct internal logic, but `SettingsSidebar.tsx` never imported or rendered them. Tests passed (each component had its own unit tests), types passed (props matched), individual PR reviews looked fine. The gap only surfaced when a user opened the page and saw nothing.

**Add an explicit integration ticket** that:

- Sequences AFTER all the component-block tickets it integrates (declared `depends_on`).
- Lists the parent file in its `files:` (e.g. `SettingsSidebar.tsx`).
- Acceptance criteria assert composition concretely:
  - "`<ChildA />` is imported in `Parent.tsx` and rendered between `<Foo>` and `<Bar>`."
  - "`<ChildB />` is rendered after `<ChildA>` with the right props threaded through."
  - "Structural test in `Parent.test.tsx` asserts every expected child renders under the conditions documented by each child's own gating logic."
  - "Manual smoke check (or e2e): visit the live route and confirm each block appears in the right state."

The integration ticket is small but essential. It's also a natural place for a `verify` skill invocation since these bugs are visible only at the rendered-page level, not the code level.

## Identify shared plumbing

Before finalizing tickets, look at the scope and ask: **does any ticket create a file that siblings will modify?** Typical patterns:

- **Wizards / multi-step flows** — the shell (`OrgWizardShell.tsx`) routes between steps; each step ticket extends the `renderStep()` switch.
- **Tabbed layouts** — the parent component composes tabs; each tab ticket adds itself.
- **Routers / dispatchers** — the parent maps keys to handlers; each handler ticket registers itself.
- **Shared hooks / contexts** — the provider defines the API surface; consumer tickets extend it.

When you spot this: the **shared file goes on every sibling's `files:` list**, not just the scaffolding ticket's. The auto-sequencer reads file overlap as "serialize these" — that's the correct behavior because two siblings can't safely edit the same file in parallel even with merge auto-rebase.

### Pre-declare shared utilities, not just plumbing

A separate but related case: **multiple sibling tickets each need the same low-level chrome** — card styles, list-row layouts, status-pill tokens, empty-state shells. These don't fit "scaffolding + step" because no single ticket creates them; each sibling independently reaches for the same shape and (without coordination) re-invents it with slightly different APIs.

When the scope contains several visually-cousin tickets (e.g. multiple "Section X re-skin" tickets, multiple "Card Y" tickets), name the shared utility files explicitly in the project description and add them to one ticket's `files:` as the canonical owner. Siblings reference the utility by path in their acceptance criteria ("uses `src/components/settings/org/cards/style.ts` for card chrome") so subagents reach for the existing file instead of independently creating `cards/style.ts` in their own subtree.

Project #5: THE-278 (Billing) and THE-281 (Dev Hub Overview) each independently invented a `cards/style.ts` in their respective subtrees — different parent paths so no collision, but the divergent shapes are technical debt waiting to be reconciled. A planning-time call-out would have prevented it.

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

## Validate acceptance criteria against the DAG

Two failure modes, both hit on the Public org events catalog project. Each cost a full pause and a human round-trip mid-run, and **both were plan-authoring bugs, not agent failures** — the agents correctly refused to stub or guess.

**1. An AC that asserts code a *later* ticket produces.**

SIGN-340's acceptance said *"with the flag OFF, `listPublicForOrg` throws NOT_FOUND."* But `listPublicForOrg` was SIGN-339's deliverable, and SIGN-339 `depends_on` SIGN-340 — so the endpoint could not exist at SIGN-340's build time. The AC was unsatisfiable by construction.

> **Check every acceptance criterion:** does the code it asserts either (a) already exist on the base branch, or (b) get produced by a ticket this one `depends_on`? If neither, the AC is filed on the wrong ticket — **move it to the ticket that owns the thing being asserted.** (Here: the gate assertion belonged on SIGN-339, which already carried an equivalent criterion.)

**2. A UI affordance with no producing ticket.**

SIGN-342's card had to render *"N of M spots left"* — but the query feeding the page returned `maxParticipants` (M) and no signup count (N), and **no ticket in the plan ever produced N**. Building the card anyway would have shipped a decorative affordance pointing at data that doesn't exist — the same "UI shipped against data that isn't there" class as the composition failure above.

> **Check every UI ticket:** enumerate the concrete fields its ACs require, and confirm some dependency's AC actually *returns* them. "Shows X" is only testable if a ticket produces X. If nothing does, either add it to the producing ticket's AC or widen this ticket's scope explicitly at plan time — don't discover it at build time.

**3. A row nobody writes.**

The two checks above ask *"who produces this field?"* Neither asks *"who creates this row?"* — and a plan can pass both while shipping a table nothing ever inserts into.

The multi-calendar project planned a `calendar_connections` table, a ticket to create the schema, and four tickets to read from it. **No ticket owned writing a row.** The gap was invisible to every existing check: the schema ticket produced the table, the service ticket produced the queries, the UI tickets consumed real fields from real endpoints. Everything was "produced" by something. But the OAuth flow returns via a *redirect*, so there was no obvious moment where a row got written, and nobody asked. SIGN-347's agent discovered it mid-build and invented a lazy reconcile-on-read (`syncConnections`) to close it — a **load-bearing design decision, made under time pressure, by an agent, because the planner never asked the question.** It happened to be a good decision. That was luck.

> **For every table or persisted entity the plan introduces, walk its full lifecycle and name the owning ticket for each step: who CREATES a row, who UPDATES it, who DELETES it.** If any step has no owner, you have found a hole — fill it at plan time. Pay special attention to rows created as a side-effect of a flow you don't control (an OAuth redirect, a webhook, a third-party callback): those are exactly the ones with no natural home, which is why they end up with none.

## Be careful when an acceptance criterion mandates literal copy

Quoting exact user-facing strings in ACs is good — it makes them testable, and it stops N parallel agents each inventing their own wording. But a quoted string is not just copy: it silently imports **a format, a convention, and a set of assumptions** into the ticket, and those can contradict another criterion in the same plan without anyone noticing.

Multi-calendar shipped an unintended visual regression this way. SIGN-349's AC specified a degraded count row reading `11:15a–12p · 2 events` — a casual 12-hour format. The grid's existing time format was `09:00–10:00`. **The same plan also demanded that a single-connection user see "zero visual change."** Both criteria were reasonable in isolation and jointly unsatisfiable: once the count row is mandated, the agent must either run two time formats side-by-side in one rail (worse) or convert every block — which changes what existing users see. It chose correctly and flagged it, but the contradiction was authored into the plan, not introduced by the build.

> **When you quote a literal string in an AC, grep the codebase for how that thing is currently rendered.** Dates, times, currency, pluralization, capitalization, truncation. If your string implies a different convention than what ships today, you have either (a) accidentally mandated a migration, or (b) written a criterion that contradicts a "no visual change" / "preserve existing behavior" criterion elsewhere in the plan. Decide which, deliberately, at plan time.

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
