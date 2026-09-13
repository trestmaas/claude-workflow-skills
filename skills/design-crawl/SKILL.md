---
name: design-crawl
description: Explore any web app in a real browser, capture a multi-viewport screenshot crawl, and surface UX/interaction inconsistencies by observation — not against a fixed checklist. Packages screenshots + manifest.json + README into a zip, builds an interactive crawl visualizer where the user marks each screen keep / redesign / direction, and emits a Claude Design handoff prompt carrying the crawl and that feedback. Use when the user wants to audit, review, or critique an app's design/UX/flow, "crawl the app", "screenshot the whole flow", "find inconsistencies", or hand a UI to Claude Design. Works on any app; personas and flows are inputs, not assumptions.
---

# design-crawl

Turn a live web app into a reviewable, feedback-ready design crawl.

The output is four things, zipped:
1. **screens/** — screenshots of every state, at every viewport asked for.
2. **manifest.json** — a machine-readable inventory: one row per screen (flow, step, job, surface, observations, severity) plus an emergent *inconsistencies* cluster.
3. **crawl-visualizer.html** — a self-contained page that renders the crawl and lets the user mark each screen **Keep / Redesign / Not sure** with free-text direction, then generates the handoff prompt from their choices.
4. **claude-design-prompt.md** — a ready prompt to paste into Claude Design.

## The one rule that makes this useful

**Explore first, judge second, and never import findings from another app.** You are not looking for a known list of problems. You walk the app, capture what is actually there, and let the inconsistencies surface from the evidence. Do not seed the crawl with categories like "surface collisions" or "modal misuse" — those are conclusions, and stating them up front biases the walk. Observe, then cluster what you saw.

Depth scales with the ask. "Take a quick look" → one persona, one viewport, the happy path. "Full audit" → every persona, mobile + desktop, edge states, and the emergent-inconsistency pass.

## Phase 0 — Scope and access (ask, don't assume)

Settle these before crawling. Guess only where a guess is cheap and reversible; state the guess.

- **Target** — base URL. Which **flows** (e.g. onboarding, checkout, settings) and which **personas** (anonymous visitor, signed-in user, admin, each distinct role). Personas usually need separate sessions.
- **Auth** — anonymous, or signed-in? If signed-in, how. See **references/access-notes.md** for the two failure modes that will otherwise waste your time (Chrome ≥136 refuses CDP on the default profile; Google/most SSO refuse automated browsers). The reliable path is email+password into an isolated automation session, or a throwaway account.
- **Mutation policy** — read-only, or may you submit real data? If writes are approved, use plus-addressed emails (`user+crawl1@…`) so mail lands in the owner's inbox, and leave optional destructive fields blank. Never confirm irreversible actions without explicit approval — screenshot the confirm dialog and dismiss it.
- **Viewports** — default mobile `390×844` first, then desktop `1280×720`. Mobile first because most real traffic is mobile and it exposes occlusion/overflow that desktop hides.
- **Output location** — default a scratch dir; deliver the final zip to `~/Desktop` unless told otherwise.

If any answer materially changes the crawl (e.g. writes on production, or which persona), use AskUserQuestion rather than guessing.

## Phase 1 — Crawl (delegate to a subagent)

Drive the browser with the **agent-browser** skill. For anything beyond a couple of screens, spawn a subagent per persona so the noisy walk stays out of the main thread and personas run in parallel. Give each subagent: an **isolated session** (`agent-browser --session <persona> …`), the safety/mutation rules verbatim, absolute screenshot paths under the work dir, and both viewports.

For every distinct state, capture: the screen at rest, and each affordance opened (menus, drawers, modals, popovers) — screenshot, then dismiss without mutating. Prefix files by viewport (`m-*`, `d-*`) and number them in flow order. Have the subagent return a walk table (step, job, surface, screenshot, note) — not the raw transcript.

## Phase 2 — Surface (observe, then cluster)

Now look across the whole crawl and write down what you *notice*, using open-ended lenses, not a scorecard:

- Where does the **same job** look or behave differently in two places?
- Where does an action's **name, placement, or affordance** drift between screens?
- Where does the app **not respond** to input (no pressed/loading/success state), or respond somewhere disconnected from where you acted?
- Where does a screen show **the wrong shape** for what it is, or leak internal concepts into user-facing language?
- What **surprised you** — anything that made you hesitate about what would happen next?
- **Mobile:** anything cut off, occluded, unreachable, or below a comfortable tap target.

These are prompts to see with, not a taxonomy to fill in. Record each observation on the specific screen it appears on. Then write the **inconsistencies** cluster: group observations that are the same underlying problem seen in different places, with the screens that evidence each. Let the categories be whatever the evidence forms — do not force them into a preset list.

Rank by user impact: **blocker** (can't complete a task) > **high** (confusing/likely error) > **medium** > **low** > **note**. Verify a claim in the code or by re-driving before you call it a blocker — a screenshot can mislead.

## Phase 3 — Package

Write `manifest.json` to the shape in **references/manifest-schema.md** (app, url, captured date, personas, flows, viewports, method, `screens[]`, `inconsistencies[]`, `gaps[]`). Then a human `README.md` indexing every screen with its observations. Zip `screens/ + manifest.json + README.md + crawl-visualizer.html + claude-design-prompt.md`.

**Validate before delivering:** every `screens[].file` exists; every image is listed; JSON parses. Deliver the zip and state what's in it and any limits (personas skipped, viewports not run, thin data).

## Phase 4 — Visualize

Copy **references/crawl-visualizer.html** and replace the `/*__MANIFEST__*/` token with the actual manifest JSON (inlined so it works from `file://` — a fetched local JSON is blocked by CORS; images load by relative path fine). The visualizer groups screens by flow, shows each with its observations, and gives the user per-screen **Keep / Redesign / Not sure** plus a direction textarea; choices persist to localStorage. Its **Generate Claude Design prompt** button merges their feedback into the handoff prompt.

Ship the HTML inside the zip (opens locally from the unzipped folder). Offer to also publish it as an **Artifact** for sharing — that path needs images embedded as data URIs (thumbnails, to stay under size limits); only do it if asked.

## Phase 5 — Handoff to Claude Design

Write `claude-design-prompt.md` from **references/claude-design-handoff.md**, filled with the app, the crawl summary, and the ranked inconsistencies — with a slot for the user's per-screen feedback (which the visualizer emits). Tell the user the two-step flow: review in the visualizer → paste the generated prompt into Claude Design. Keep the prompt neutral about *solutions* — it hands Claude Design the evidence and the user's direction, and asks it to design within stated constraints, not to rubber-stamp a predetermined fix.

## Notes

- This skill finds and frames problems; it does not fix code. If the user wants fixes, that's a separate follow-up.
- Keep the crawl reproducible: record the exact URLs, personas, viewports, and session names in the manifest `method` field so a re-crawl after changes is apples-to-apples.
