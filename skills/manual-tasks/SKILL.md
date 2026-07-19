---
name: manual-tasks
description: Standing backlog of work only a human can do — env vars, DNS, dashboard config, third-party signups, decisions. Other skills file into it mid-run without halting; `/manual-tasks` walks the open list, doing what it can and asking for the rest. Reads `.claude/conventions.yaml` for the Linear team and evergreen project.
---

# /manual-tasks

The agent-side half of "things I need to do by hand." Skills **file** into it; this skill **works it down**.

## The boundary that makes this work

Before this existed, an agent had exactly one channel for human work: `needs input:`, which **halts the ticket**. So an agent that discovered "this needs a Vercel env var before it works in prod" had to either block otherwise-shippable code, or bury it in a run report nobody re-reads. It was always the second, and that's what got lost.

- **`needs input:`** — blocking, needs an *answer* now, halts one ticket. Unchanged.
- **A manual task** — deferrable, needs an *action* in an external system, does **not** block the merge.

If you're about to `needs input:` something the human could do later without stalling you, file a manual task and keep going instead.

## Conventions

```yaml
manual_tasks:
  team: thesignup                      # defaults to linear.team
  project: "Manual tasks (evergreen)"  # created on first use if absent
  label: manual
```

The project is **evergreen**: never marked Completed, no `.handoffs/` bundle, never an execution target. `/project-start` and `/project-retro` skip it.

If the project doesn't exist for a team, create it (state `started`, label every ticket `manual`) rather than pausing.

## Filing a task

Other skills call this path. **File anything a human must do outside the repo** — env vars, DNS, dashboard config, OAuth consent screens, key rotation, third-party signups, feature-flag flips, a decision only the user can make. Err toward filing: an over-full list is cheaper to prune than a missing item is to rediscover.

Do **not** file: anything you could just do yourself, and anything already covered by an open task (search the project first — duplicates are the fastest way to make the list unreadable).

`mcp__claude_ai_Linear__save_issue` with the configured team, project, and `labels: ["manual"]`. Body must answer four things:

```markdown
**Why** — <what needs this, linking the ticket/PR that surfaced it>

**Do this**
1. <literal steps or commands, not a description of them>

**Verify** — <how to tell it's actually done>

**Until then** — <what stays broken or inert>

*Filed by <SKILL> during <TICKET-ID>.*
```

**The Verify line is the one that matters.** Without it you build a list you can't close, because in three weeks you won't remember whether you already did it — and neither will the agent. "Do this" written as a description ("set the API key") rather than a command (`vercel env add RESEND_API_KEY production`) has the same failure: you have to re-derive the task before you can do it.

Set priority **Urgent** only when shipped code is inert or broken until this happens. Otherwise leave priority unset. This is the sole tier — don't invent more.

After filing, mention it in your run output (one line, with the id). Filing silently defeats the point.

## Reviewing — the `/manual-tasks` run

### 1. Load

`mcp__claude_ai_Linear__list_issues` on the configured project with `state` filtered to non-done. Also query `label: manual` across the team and report anything with the label but not the project (or vice versa) — that's a filing bug worth seeing.

Order: Urgent first, then oldest-created. Age is the signal that matters; a task nobody has done in six weeks is either not real or genuinely stuck, and both are worth surfacing.

### 2. Pre-verify before asking for anything

For every open task, run its **Verify** step first — read-only, no confirmation needed. Some are already done and never got closed; closing those costs you nothing and shortens the list before the user looks at it.

Close anything that verifies as already-done, with a comment saying what you checked.

### 3. Walk the remainder, one at a time

For each task, do the parts you have access to, then hand back what's left.

**Act without asking** when the action is additive and reversible — adding an env var, creating a resource, reading config, running a check, updating Linear. Report what you did.

**Confirm first** when it is destructive, irreversible, spends money, or is visible to real users — rotating or deleting a credential, changing billing or plan, touching DNS on a live domain, flipping a flag that changes production behavior, anything against real user data. State the exact command and wait. Approval on one task does not carry to the next.

**Hand back** what needs the user's own hands or credentials — a dashboard with no API, an account only they can create, a decision only they can make. Print the literal steps and move on; don't stall the walk waiting on it.

After each, re-run Verify and close on success. If Verify fails after you acted, say so plainly and leave it open — a task closed on an unverified action is worse than one left open, because it stops being visible.

### 4. Report

```
result: manual tasks — N closed (M auto-verified), K need you, P deferred
```

Then the "need you" items as a short list with their steps, so the user has everything in one place without opening Linear.

## `/manual-tasks add <description>`

File one by hand from the current conversation. Fill the four fields from context; ask only for what you genuinely can't infer. Useful when the user notices something mid-conversation and doesn't want to lose it.

## What this skill does NOT do

- Does not write code or open PRs. If the fix is code, it's a normal ticket — use `/start`.
- Does not mark the evergreen project Completed. Ever.
- Does not close a task on a report alone — only on a passing Verify, or an explicit "done, trust me" from the user.
- Does not re-file a task that's already open. Search first.
