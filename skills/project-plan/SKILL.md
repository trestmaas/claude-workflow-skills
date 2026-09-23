---
name: project-plan
description: Turn an idea into a well-structured Linear project ready for hands-off parallel execution. Conversational — asks clarifying questions before scaffolding. Outputs a Linear project, per-scope-item tickets, and `.handoffs/<slug>/tickets.yaml` — the machine contract /project-start consumes (with file surface and per-ticket dependencies). Reads `.claude/conventions.yaml` for Linear team / ticket-prefix conventions. Requires the `/grilling` and `/domain-modeling` skills (mattpocock/skills).
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

## Plan against `origin/main`, not your local checkout — fetch first

**Before any probing or ticketing, run `git fetch origin` and plan against `origin/main`.** A local `HEAD` can be hours stale, and every premise you verify against a stale tree is a coin-flip.

On the participant-flow-repair project the planner ran `git log` without fetching; local `main` was **21 commits behind** `origin/main`. In that gap, other work had already fixed bugs the plan was about to file, shipped a data-model the plan was about to duplicate, and turned one "bug" into deliberate security design. **Four of eighteen tickets were cancelled at execution time** for this single omission — including two where building the ticket as written would have *reintroduced a security hole* the codebase had just closed.

Concretely, at plan start:
- `git fetch origin` and note how far behind you are: `git rev-list --count HEAD..origin/main`. If it's non-zero, **every file:line you cite must be verified against `origin/main`** (`git show origin/main:<path>`), never the working tree.
- When you quote code in a ticket ("`foo.ts:88` is a ternary"), you are asserting it's true *now*. Read the body on `origin/main`, not from memory or a skimmed grep — a signature is not an implementation (one ticket wired a checkbox to a procedure that turned out to be a `console.log` stub returning `success:true`).
- Re-verify at execution time too: every `/start` prompt should tell the agent to `git fetch` and branch from the fetched `origin/main`, and to **stop and report if a premise is already fixed** — treat "this is stale" as a *success*, not a failure. That instruction is what let subagents catch the planner's stale-tree errors before they shipped.

## Cross-check other in-flight `.handoffs/` bundles before writing tickets

`/project-plan` is often run while *other* planned projects are executing in parallel. Enumerate them — `ls .handoffs/*/tickets.yaml` — and skim each for overlap with your scope **before** writing tickets. On participant-flow-repair, one ticket (a plus-one data model) turned out to duplicate the entire first half of a separate `p4-rsvp-first-class` project whose foundational ticket had merged two hours earlier; two projects building the same primitive is the worst outcome. Flag overlapping scope, **shared files** (two projects editing one file race at merge), and **migration-number collisions** (both projects claiming `0060_*.sql`) in the project description, and re-scope or cancel the overlap at plan time.

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

## A grilling decision that names an artifact must first read what the artifact is

When a decision under discussion says "X counts as proof / ownership / identity" — a cookie, a token, a header, a link — read X's *definition* in the code before recording the decision, not its name in the ticket prose. On Access Token the SIGN-1387 decision listed the Identity Cookie as a proof source because the ticket said so; the cookie carries a signed *email*, never a token, and is obtainable for any address by registering it. The code correctly refused it and the decision had to be amended after the fact. One `sed -n` on `signup-identity-cookie.ts` during grilling would have kept the decision and the code in agreement from the start. Grilling already looks facts up rather than asking; the definition of an artifact a decision hinges on is such a fact.

## An acceptance criterion that asserts a fact about the code must carry the derivation, not the fact

When an AC states a number, a file list, or "X is a Y", **write the command that produces it instead of the answer**. `grep -c "\.foo(" src/server/services/bar.ts → 0` is an AC; "the four sites in `bar.ts`" is a guess with a number in it.

On Dashboard Actor, **four ACs across three tickets were false or unmeetable**, and every one asserted a property of the tree the planner had not derived:

- "five sites" where two of them were containment loaders called by eleven methods — the real blast radius was fourteen operations, nearly 3x the ticket.
- "`date-place-invariant.db.test.ts` passes untouched" — it calls the service directly, so the signature change reaches it.
- "a row of another event under the same org is `NOT_FOUND` for every actor" — false for a method that takes no event id, where authorization follows the row. Two separate tickets hit this same shape.
- "keep the two `FORBIDDEN`s as role rules after a passed resolver" — **unmeetable**: both live in a token-keyed method that cannot have a resolver, because one would have to admit someone not yet on the roster.

The worst of them would have deleted a product feature: an AC describing `cloneForUser` as an inline creator check, when it is a growth loop where a stranger cloning a *published* signup must succeed. Building it as written reds **45 cases across seven suites**.

Every one was caught by an agent that stopped and reported rather than forcing the AC — which is the behaviour to keep, and why "stop and report a false premise is a valued outcome" belongs in every `/start` brief. But the cost is a stalled ticket each time, and a specific-and-wrong AC is far more dangerous than a vague one, because it reads as authority. **The derivation fails at grep time; the assertion fails at build time.**

Two corollaries worth stating in the ticket itself:

- **If an operation takes no event id, say authorization follows the row** and name the path that must refuse, rather than claiming blanket containment.
- **A count is a ceiling only if you re-derived it at plan time against `origin/main`** — and the AC should tell the agent to re-derive it anyway.

## Every number a plan or a PR publishes is re-derived against the state being published

Not against the state you were in when you wrote it down. On Dashboard Actor the closing ticket's own Outcome table — headed *"Re-derived rather than copied; each figure is the output of the command beside it"* — published a file count that was the union **without** the closer, under a heading naming the closer. Cause: the script ran *before* the closer's own work was committed, so `git diff --name-only origin/main...HEAD` returned nothing and the union silently degraded by one PR. The author saw the `0`, re-derived correctly for the PR body after committing, and never went back to the table already written.

That was the **sixth** instance in one project of a single defect: *an unverified claim stated flatly*. The others: an unqualified permissions claim false for soft-deleted orgs; a verifying grep whose path list excluded the only file containing the hit, run clean by three separate tickets; a RED run credited with proving a displacement it structurally could not; a helper's naming justified by a scan that never reads that method; and a count low by 5x.

None is catchable by a gate, and all six were caught by a human-facing review. So:

- **Prefer one place that derives a figure, with every other place quoting it.** Two artifacts holding the same number independently will disagree, and the durable one is usually the stale one.
- **Re-run the derivation last**, after the final commit, before publishing.
- **State what a proof does *not* cover.** "This RED run proves the call-shape change and the closed oracles; it does not demonstrate the refusal displacement — that is proven by X" is worth more than a longer list of what it does.

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

### Declare the sibling TEST files a shared component drags in

The single biggest source of file-surface drift is invisible in the source tree: **when a ticket adds a tRPC query, hook, or prop to a shared component, every existing test file that mocks that component must also change** — because their hand-written mocks now lack the new procedure and the component throws. These test files are nowhere in the ticket's conceptual scope, so they get omitted from `files:`, and the drift only surfaces at build time.

On "Monetize the AI creation flow", **7 of 10 tickets** touched undeclared files, and the majority of that was this one pattern: SIGN-609 and SIGN-612 each had to edit **four** existing `CreateSignupWizard.*.test.tsx` files to add a `draftAllowance` mock, none of which they'd declared. Two tickets, eight undeclared test files, one cause.

So at plan time, for any ticket whose deliverable adds a query / hook / context-value / required prop to an **existing shared component**: grep for who already mocks it —

```
grep -rl "<ComponentName>\|trpc\.<router>\.<newProcedure>" src/**/__tests__ src/**/*.test.*
```

— and add every hit to that ticket's `files:`. This both makes the drift honest and lets the auto-sequencer serialize correctly against any sibling touching the same test files. If you can't enumerate them at plan time, say so in the ticket ("expect to update existing `CreateSignupWizard` test mocks — enumerate at build") so the executing agent treats it as expected work rather than unplanned scope.

**The same rule applies to any change of a shape that fixtures spell out — not only to shared components.** On Access Token, 3 of 4 PRs touched 15–21 undeclared *test* files for one reason each: a procedure input gained a field (`slug`), an actor union lost a member (`public-form`), a service signature narrowed (`{ userId }`). None of those is "a query or prop on a shared component", so the rule above did not fire, and the drift was almost entirely tests. So: for any ticket that changes a procedure input, an actor/enum union, or a service method signature, grep for the *old* spelling in test files at plan time —

```
grep -rl 'kind: "public-form"' src --include=*.test.*
grep -rl 'getSignupsByToken(' src --include=*.test.*
```

— and declare every hit. Had the drift been in source files this would not be the fix; it was the fixtures.

**A procedure that does not exist yet cannot be grepped — declare the mocks by their parent, not by the name.** The rule above greps the *old* spelling, which works for a field or a union member that already exists. It under-counts when the ticket *creates* the thing: on One Actor a new tRPC procedure (`events.publishDraft`) broke 21 component tests whose strict router mocks list every procedure they expect, and a deleted one (`listForActiveOrg`) orphaned 22 more. Neither name existed at plan time to grep for. So for any ticket that may **add or remove a tRPC procedure** (or any strictly-mocked module's export), declare the mock files by their parent instead:

```
grep -rl "events: {" src/components --include='*test*'     # strict mocks of the events router
```

Every hit is expected surface. The mocks fail on a new procedure regardless of its name, so the name is not needed to predict them.

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

### A persisted field drags in every wire schema on its path

The test-mock pattern above has a source-tree twin, and it is quieter: **when a ticket adds a field to a persisted shape, every zod schema between the UI and the row must be widened or the value silently vanishes.** Zod strips unknown keys by default, so a field the UI sends, the service accepts, and the column stores can still arrive as `undefined` — because one tRPC input, one REST body, one MCP tool schema, or the wizard's publish schema in the middle never named it. Nothing throws. Typecheck is green. The only witness is a db test that reads the row back.

On the participant-questions project this was the dominant cause of file-surface drift — **5 of 14 tickets** (SIGN-1292/1293/1294/1295/1300) each had to touch two to four wire schemas nobody declared, and SIGN-1293's premise ("the wizard never sends `customField`") turned out to be true *twice over*: the mapping was missing **and** the publish schema behind it would have stripped the key anyway. One ticket's own comment in the router already documented the identical failure for a `label` field, from a previous project.

So at plan time, for any ticket that adds a field to something persisted: **enumerate the path from the control to the column and put every schema on it in `files:`** —

```
grep -rn "<siblingFieldName>" src/server/routers src/server/openapi src/server/mcp src/app/api src/components/**/publish
```

— where `<siblingFieldName>` is a field that already travels the same path (the one the new field sits beside in the row). Every file that names the sibling must name the new field too. Add the hand-built test mocks of each (the section above) while you are there. If the path cannot be enumerated at plan time, say so in the ticket ("widen every wire schema between `ItemFieldsRow` and `items.ask_details`; enumerate at build") so the agent treats it as expected work.

Had the drift been confined to UI files, this would not be the fix. It was not.

## A "model on existing X" instruction inherits X's bugs — spot-check the precedent first

When a ticket tells an agent to clone or mirror an existing surface ("model on the org-logo route", "same pattern as the avatar upload"), the agent will faithfully reproduce it — **including any latent defect in the precedent.** A clone is only as safe as what it copies, and a security-relevant flaw propagates silently because the ticket *told* the agent to match.

On the Event-cover-images project, SIGN-624 was scoped "model on `src/app/api/orgs/[id]/logo/route.ts`" and did exactly that — inheriting a cross-tenant blob-delete IDOR (a substring `includes()` tenant check bypassable via query string) that ships in the avatar and org-logo routes today. Independent review caught it in the new route, but the same bug lives on unreviewed in the precedent it was copied from (filed as a follow-up).

So, before writing "model on X" into a ticket: **read X's security-relevant lines** — authz checks, tenant/ownership containment, input validation, path/URL parsing. If X has a flaw, either (a) point the ticket at a corrected pattern and note the fix in its ACs, or (b) file a follow-up ticket for X and tell the new ticket not to copy the flaw. Don't hand an agent a precedent you haven't vetted.

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

**4. A capability built before its storage, with nothing scheduling the join.**

The checks above ask who produces a field and who writes a row. None asks *when a control becomes reachable relative to the thing that persists what it produces* — and a plan can pass all three while shipping a feature that is either inert or actively wrong for the window between two merges.

Cover-image-cropper split "rewrite the cropper" (which owns the ratio picker) from "wire the create wizard" and "wire the edit page" (which own the field that stores a chosen ratio). Correct decomposition. But the picker defaults **on**, so the moment the cropper merged, an organizer could pick 1:1 — and the wizard, still typing that field as a bare string, dropped the choice and re-cropped their image to 16:9, losing ~44% of its height. Every ticket's tests passed. The defect existed only in the *interval*.

The author caught it in review and shipped a `showRatioPicker={false}` stopgap at both call sites, with source comments naming the two successors. That worked — but only because the orchestrator hand-carried "remove this" into both later briefs. **Nothing in `tickets.yaml` encoded it.** Had either brief omitted it, the project would have merged 13/13 green with its headline capability permanently disabled, and every test would still have passed, because the tests were written against the stopgap.

> **When one ticket exposes a capability whose storage or consumer lands in another, decide at plan time which of these you want, and write it down:**
>
> - **Sequence it** — make the storage ticket a `depends_on` of the ticket that exposes the control, so the interval never exists. Cheapest when the DAG allows it.
> - **Ship it dark** — the exposing ticket defaults the control off, and **the successor carries "remove the `<flag>` stopgap and invert the guard test asserting it is absent" as an explicit acceptance criterion.** Not a code comment. A criterion, on the named ticket, in `tickets.yaml`.
>
> A stopgap recorded only in source is a promise no check can keep. And note the second half of that criterion: a guard test asserting the control is *absent* must be **inverted, not deleted**, or the successor can satisfy its AC by removing the evidence.

The general form, worth applying beyond feature flags: **any deliberate temporary state one ticket leaves for another to clean up is scope that belongs to the successor's acceptance criteria.** Dead code awaiting a consumer, a widened type awaiting a narrowing, a duplicated constant awaiting extraction — same shape, same failure mode.

**5. A writer that lands before its collector, while a gate is already live.**

Check 4 is about a control and its storage. This one is about three tickets, not two: a **gate** that refuses input missing some answer, a **writer** that creates the thing the gate judges, and a **collector** that gives the user a place to answer. The DAG can order gate → writer → collector and pass every check above — the gate has its own tests, the writer produces real rows, the collector consumes real fields — while the product is unusable for the interval between the writer's merge and the collector's.

Participant-questions did exactly this. SIGN-1300 (the server gate: a Required Day Question blocks registration) merged first. SIGN-1294 (the wizard, the first writer of Day Questions) was review-clean and CI-green next. SIGN-1301 (the review page, the only place a participant can *answer* a Day Question) was still building. Had #1429 merged on schedule, an organizer could have published a required question and every new signup on that event would have been refused with an error nobody could satisfy — on a repo that deploys `main` to production. The independent reviewer caught it; the orchestrator held the PR ~5h. **Nothing in `tickets.yaml` encoded it**, because no file overlapped and no `depends_on` pointed the right way.

> **For every enforcement ticket in the plan, name who writes the data it judges and who collects the answer it demands, and order the writer after the collector** — `depends_on`, in the yaml. If the DAG cannot afford that (the writer is on the critical path), the writer ships dark (check 4) with the collector carrying the un-darkening criterion.

Had the gate and the collector been one ticket, or had the writer been the last ticket, this check would fire on nothing. It fires exactly when enforcement is split from input across a merge boundary — which is what parallel execution does by default.

## Be careful when an acceptance criterion mandates literal copy

Quoting exact user-facing strings in ACs is good — it makes them testable, and it stops N parallel agents each inventing their own wording. But a quoted string is not just copy: it silently imports **a format, a convention, and a set of assumptions** into the ticket, and those can contradict another criterion in the same plan without anyone noticing.

Multi-calendar shipped an unintended visual regression this way. SIGN-349's AC specified a degraded count row reading `11:15a–12p · 2 events` — a casual 12-hour format. The grid's existing time format was `09:00–10:00`. **The same plan also demanded that a single-connection user see "zero visual change."** Both criteria were reasonable in isolation and jointly unsatisfiable: once the count row is mandated, the agent must either run two time formats side-by-side in one rail (worse) or convert every block — which changes what existing users see. It chose correctly and flagged it, but the contradiction was authored into the plan, not introduced by the build.

> **When you quote a literal string in an AC, grep the codebase for how that thing is currently rendered.** Dates, times, currency, pluralization, capitalization, truncation. If your string implies a different convention than what ships today, you have either (a) accidentally mandated a migration, or (b) written a criterion that contradicts a "no visual change" / "preserve existing behavior" criterion elsewhere in the plan. Decide which, deliberately, at plan time.

## A foundation ticket's ACs must enumerate every rule, not summarize

When a ticket's deliverable is a data-driven **registry / config / rule-table** that N sibling tickets consume (an action registry, a capability map, a permission set), its acceptance criteria must specify the rule for **each entry explicitly**, and its tests must assert each — because a summary reads as complete while shipping a hole that only surfaces three tickets later.

On P1, SIGN-405's registry AC said "Move/Remove don't apply to a headcount row." The agent implemented the *move* gating (via `slotCount`) and never hid *remove* or *resend* — "Move/Remove" read as one rule but was two, and the gap stayed invisible until SIGN-416 tried to converge onto the registry and hit a merged sibling's test. It forced a mid-run `needs input:` pause and a scope expansion. "Move/remove" is not one rule. If the deliverable is a table, the AC is a table: one falsifiable row per entry, per surface it feeds.

## A count quoted in an AC must come from the tool that will later verify it

When a ticket's deliverable *is* a scanner, enumerator, or guard — a lint rule, a source-scanning test, a registry check — every downstream ticket that quotes a count ("the three primitives hold 51/36/25 physical utilities", "24 activity kinds", "≤ 230 sites after cleanup") is quoting a number the scanner has not yet produced. A regex over source is not the scanner: it matches the same token in prose, in comments, in selector text, in sub-object discriminators. The number reads as verified and is wrong on arrival.

On i18n-readiness this happened twice in one plan. The per-file CSS counts (51/36/25) came from a grep that also matched `left`/`right` inside Radix `data-[side=…]` selectors; the real scanner (SIGN-1306) said **11/8/3**, so SIGN-1308's "a third of the baseline" premise and SIGN-1319's "≤ 230" AC were both false. The "24 activity kinds" came from grepping `kind: "…"` across writer files; five of those were sub-object discriminators never passed to `record()`, and the golden-table AC pinned a completeness number of 24 for a union of **19**. Both were caught by the executing agents and cost a mid-run Linear patch each — cheap, but only because the orchestrator was watching.

> **Sequence the scanner ticket first, and in every dependent write "N — measured by SIGN-xxxx's tool at build time" instead of a number.** If the plan needs a figure for sizing, label it an estimate and name what it was counted with. An AC that pins a number the ticket's own tool will contradict is a false green waiting to happen; a `≤ <measured>` pinned at the prune ticket is the honest form.

## A ticket that unifies N paths must inventory each path's RULES, not just its auth and side effects

The sibling of the count rule: when a ticket merges two (or more) code paths into one, the plan's divergence table is what the executing agent builds to — so a row the table does not have is a difference nobody resolves. On One Actor the table had four rows (authorization, not-found shape, rules, side effects) and was filled by reading the *pairs the ticket named*. Both blocking defects were rules one path had and the other lacked, and one of them lived on a **third** path the table never listed: the dashboard published through `update({ status: "published" })` while the API used `publish()`, and only the latter refused a closed event — so a free-tier organizer could resurrect a closed event past the hosting cap. The same shape appeared twice more (webhook writes gated owner/admin on one path only; the headcount rule on one path only).

> **For every ticket that unifies N paths: before building, enumerate each path's rules from the tree — every `assert*` / `require*` call and every inline `throw` in its body — and put them in the PR body as a per-path table. Every asymmetry is either resolved in the ticket or named as deliberate.** Enumerate by *operation*, not by the pair of names the ticket happens to use: grep for every caller that reaches the same write (`grep -rn "status: \"published\"" src` found the third publish path). The reviewer re-derives the table rather than reading it. Would have been wrong to recommend if the defects had been in the rows the table already had.

## A "make N doors/writers agree" ticket must carry the grep that enumerates N

The sibling failure to the one above: the count is not of things a tool will later produce, but of things that already exist on `origin/main` — callers, writers, doors — and the planner counted them from memory or a skim. On Access Token the author's count was wrong twice in one project: "seven client callers" (there were eight — `useReviewSubmit.ts`) and "two writers of `event_signups.user_id`" (there were three — public `signups.create`). The second miss would have made the follow-up unlink migration silently non-durable; the reviewer found it, not the author. On the timezone ticket that followed, the planner ran the grep first and it turned up two writers the original architecture review had missed entirely.

> **A ticket that says "N" must say "N — enumerated on `origin/main` by `<grep>`; the PR body lists them", and the reviewer brief carries the same grep.** The grep is the claim; a number without one is a guess that reads as a measurement. Would have been wrong to recommend if the counts had held.

## A guard's ACs must name the ways of being unclassifiable, not just the thing it catches

When a ticket's deliverable is a scanner, a ratchet, or a source-scanning test, its fixtures will test the shapes the author thought of — and a guard that quietly *passes* what it cannot parse is worse than none, because the PR body will say it is enforced. On One Actor three guards shipped and an adversarial reviewer broke two of them in minutes: the rule-set scan was satisfied by the rule's *name* in a comment, by a call with the wrong argument, by a call placed after the write, and by a one-character allowlist entry; the schema guard passed a `z.object({…}).extend({ eventId })` and a non-identifier argument, both silently, while its docblock claimed it "refuses what it cannot classify".

> **For any ticket whose deliverable is a guard, the AC enumerates the ways an input can be *unclassifiable* — not only the violation it catches — and requires a fixture per way proving a loud refusal.** A scanner that returns "no finding" and one that returns "cannot tell" must be different results. Then add to the reviewer brief: *try to satisfy the guard without doing the thing* — the name in a comment, the call with the wrong argument, the call after the write, the allowlist entry, the shape the regex does not reach. Had the guards held under those attempts, this would not have been the fix.

## A ticket that adds a repo-wide guard must check the PRs already open

A new filesystem-globbed guard — a lint rule with a baseline, a source-scanning test, a ratchet — is evaluated against `main` the moment it merges. Every PR open at that moment was tested on a base that did not have the guard. If required checks are not `strict` (they are not on thesignup), a PR green on the stale base merges past the guard, and `main` goes red for everyone until someone notices.

On i18n-readiness, SIGN-1273 (another project) added `pl-[3.25rem]` on a branch cut before the CSS guard existed, merged six minutes after the guard, and turned `main` red for 35 minutes; four of this project's armed PRs sat blocked until a one-token hotfix landed and each branch was updated from `main` (a `gh run rerun` replays the *old* merge ref and does not help). The same ticket's own test fixture used `border-lime-200` as a "look-alike" token and tripped the pre-existing brand-palette guard — the new guard's fixtures are inputs to every other guard.

> **Add two ACs to any ticket that introduces a repo-wide guard:** (1) "Run the guard against every open PR's merge ref (`gh pr list --state open`, then the scanner on `refs/pull/N/merge`) and list in the PR which would fail; either fix them in this PR or file the follow-up before merging." (2) "Run every other filesystem-globbed guard in the repo against this PR's new files and fixtures." Name the other guards in the ticket; the executing agent will not know they exist.

## An example in an AC must actually reproduce the bug

A bug ticket usually quotes a concrete input — the email that overflows, the title that wraps, the payload that 500s. That example is not illustration. It is **the thing the agent will write its test against**, so a plausible-looking example that doesn't actually reproduce the bug is *worse than no example*: it manufactures a false green. The agent writes the test the AC asked for, watches it pass, and ships a fix it never proved.

This applies to **geometry and threshold assertions too, not just string/value inputs.** On P1, SIGN-428's e2e was authored to prove the participant detail was "a centered modal, not a right-hugging drawer" via `box.x + box.width < viewportWidth - 1`. That assertion *passed for the drawer it was meant to reject* — a ~460px drawer's right edge lands ~15px short of a 1280px viewport, so only the (also-present) height check would have caught it. The agent found it, replaced it with a real centered-check, and verified red against the drawer before shipping. When an AC quotes a pixel bound, a timeout, a percentage, or any numeric threshold as the discriminator, **compute it against the actual reject-target at plan time** — the same "run it before you quote it" rule the value-input case demands.

Mobile-responsive-fixes authored this twice in fifteen tickets:

- SIGN-363's AC quoted `christopher.wolfeschlegelstein@example-domain.org` as an email that overflows its box. It contains a **hyphen**, and Chrome breaks lines at hyphens — it wraps unaided. The AC's `scrollWidth <= clientWidth` assertion was green *without the fix*.
- SIGN-368's AC quoted a 51-character location as one that forces sideways scroll. It overflows the header *row* but not the *document* — it spills into the page's own 16px padding. Also green without the fix. It took 72 characters to genuinely scroll the page.

Both were caught only because the executing agents reverted their fix and confirmed the test went red. Neither would have been caught by review, by CI, or by the criterion itself.

> **Before you write a concrete example into an acceptance criterion, run it.** Reproduce the bug with that exact value — in a browser, a REPL, a scratch test, whatever's cheap. If it doesn't reproduce, find a value that does and quote *that*. If you can't reproduce it at plan time, say so in the ticket ("repro value not verified — confirm before writing the test") rather than presenting an unverified example as if it were the spec.

This is the single highest-leverage check in this skill. Hands-off parallel execution cannot self-detect a test that is green for the wrong reason.

### Never prescribe an assertion that cannot go red

The example is one way to manufacture a false green; the **assertion itself** is the other. When an AC dictates *how* to test — and layout/CSS ACs almost always do — it is easy to prescribe an assertion that passes against the broken code, so the agent writes exactly what you asked and ships an unproven fix. participant-flow-repair authored three of these, one of them in an AC written specifically to *prevent* false greens:

- **Class-name assertions.** ACs demanded the fix be verified by `expect(el.className).toContain("break-all")` (and three existing tests did the same). The class *is* the bug; asserting its presence passes while the page is visibly broken. A Tailwind arbitrary-value class is worse still — it can be typed in source but never emitted by the build, so a class-name assertion is green whether or not the style exists.
- **`getClientRects().length === 1` on a block element.** An AC prescribed this to prove a heading no longer wraps. `getClientRects()` on a block returns **one border-box rect no matter how many text lines it holds** — the assertion is `=== 1` before and after the fix. It can never go red. (The honest version counts line boxes with a `Range` over the heading *text*: `range.getClientRects()`.)

Rules for any AC that mandates a test:
- Assert a **rendered/computed property**, never a source token: line boxes via a `Range`, `getComputedStyle().overflowWrap`, `elementFromPoint`, measured geometry. Never a `className`, and never a single block-level rect count.
- Require the ticket to **prove red-before-green by reverting only the fix** — the agent must watch the test fail against the unfixed tree, and for a class/CSS fix, strip *only* the changed class from a real build and confirm it goes red (a subagent caught an inert Tailwind fix exactly this way).
- If you cannot construct a falsifiable assertion at plan time, say so in the ticket rather than prescribing one that can't fail. A wrong prescribed assertion is worse than none — the agent trusts it.
- **When the decision changes where a user lands, the e2e must walk the app's own navigation.** Any AC of the form "after X the user can still Y" is satisfied only by a spec that reaches Y through the UI's own links and redirects, never by `page.goto`-ing the destination. On Access Token the first re-attend spec went straight to `/manage?token=` and passed; the reviewer asked for the real flow (cancel → landing → pick → save) and it failed on a cleared client stash that no unit test could see. This does not fire on a pure server ticket.

## Sequence global-chrome tickets ahead of layout-measuring ones

When one ticket changes something **global** — a CSS rule on `html`/`body`, a shared layout wrapper, a root provider, a base font size — and another ticket **measures** what the global thing affects, they are not independent, even when their file surfaces don't overlap. The file-surface auto-sequencer will not catch this: the conflict is in the *rendered result*, not the source tree.

Two instances in one project, both discovered in CI rather than at plan time:

- SIGN-373 added `html { overflow-x: clip }`. That makes `document.documentElement.clientWidth` report the **clip box** rather than the content width — so SIGN-374's viewport-width assertions started measuring the wrong ruler and its CI went red. The code was correct; the yardstick wasn't.
- SIGN-366 added a mobile affordance to a page whose above-the-fold contract SIGN-364 had asserted in e2e. The new row pushed the first slot below the fold and correctly failed SIGN-364's test.

Both are *good* outcomes — the tests did their job — but each cost a red CI and a debugging round-trip that an explicit edge would have prevented.

> **At plan time, ask: does any ticket change a global that another ticket measures?** Global CSS, root layout, shared providers, viewport meta, base typography. If yes, add an explicit `depends_on` so the global lands first and the measuring ticket is written against the world as it will actually exist. Note it in the dependent's description too, so the agent knows *why* it's sequenced.

## Manual setup is not a ticket — file it, don't schedule it

Planning routinely surfaces prerequisites that no agent can execute: an API key that has to be generated in someone's dashboard, a DNS record, an OAuth app that needs a consent screen, a third-party account, an env var that must exist in Vercel before the feature does anything.

Do **not** turn these into tickets in `tickets.yaml`. A ticket in the bundle is a promise that `/start` can pick it up in a worktree and merge a PR — and `/start` cannot log into a dashboard. Scheduling one guarantees a spawned agent, a burned worktree, and a pause.

Instead, **file each as a manual task** per `/manual-tasks`, at plan time, before the project starts. Then:

- If a *ticket* can't work until the manual task is done, say so in that ticket's description ("requires <TASK-ID>: `RESEND_API_KEY` set on Production") so the `/start` agent knows why its feature won't come alive locally, and doesn't go looking for a bug that isn't there.
- Report the count in your final line so the user can clear them while the project runs, rather than discovering them at merge time.

The `external_depends_on` field is for foreign *tickets*, not for these — a manual task has no PR and no Done-via-merge, so don't wire it into the DAG. It runs alongside the project, not inside it.

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

If you filed any manual tasks, add: `manual: K task(s) filed — <ids>`.
