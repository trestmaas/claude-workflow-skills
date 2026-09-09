# Claude Design handoff prompt — template

Fill the `{{…}}` slots from the manifest and the user's visualizer feedback.
Keep it evidence-first and solution-neutral: hand over what's *there* and the
user's *direction*, and let Claude Design propose the design. Do not prescribe
the fix, and do not carry over findings or aesthetics from any other app.

The `crawl-visualizer.html` **Generate Claude Design prompt** button produces a
filled copy of this automatically from the user's per-screen choices — this file
is the template it uses and the fallback if they'd rather fill it by hand.

---

```
I'm redesigning parts of {{APP}} ({{URL}}). I ran a design crawl — screenshots
of every screen across {{FLOWS}} at {{VIEWPORTS}} — and reviewed each one. This
is an exploration, not a spec: I want you to design the fix, not confirm mine.

WHAT THE CRAWL FOUND (surfaced from the screens, ranked by user impact):
{{INCONSISTENCIES}}
  e.g. — [high] The same action is named three different ways across the flow.
       — [high] Confirm dialogs use opposite button colors for the safe vs.
         destructive choice.
       — [medium] Mobile: the primary control is covered by a sticky bar at rest.

MY DIRECTION, PER SCREEN (from my review — Keep = leave it, Redesign = change it):
{{FEEDBACK}}
  e.g. — screens/m-03-checkout-review.png — REDESIGN — "make the destructive
         action obviously secondary; I don't care how, but it must not read as
         the primary."
       — screens/m-07-confirmation.png — KEEP.

CONSTRAINTS (respect these; ask if any block you):
{{CONSTRAINTS}}
  e.g. — Stay within the existing design system / tokens / component library.
       — Mobile-first; every control reachable at 390px.
       — Don't introduce new dependencies.

WHAT I WANT BACK:
1. For each REDESIGN screen: a concrete proposal — layout, states, and the
   interaction — with a short rationale tied to what the crawl showed.
2. Where several screens share one underlying inconsistency, one coherent rule
   that resolves all of them, not per-screen patches.
3. Call out any tradeoff you're making rather than silently picking.
4. Leave the KEEP screens alone unless a change is load-bearing for a fix — and
   if so, say why.

Attached: the crawl screenshots and manifest.json. Work from the actual screens.
```

---

## Filling the slots

- **`{{INCONSISTENCIES}}`** — the manifest `inconsistencies[]`, each as
  `[severity] summary`. These are the emergent clusters, in the app's own terms.
- **`{{FEEDBACK}}`** — the user's per-screen verdicts from the visualizer:
  `file — KEEP|REDESIGN|NOT SURE — "their direction note"`. Include every screen
  they marked; omit the ones they left untouched.
- **`{{CONSTRAINTS}}`** — ask the user, or infer from the codebase (design
  system, framework, platform). If unknown, leave a single line telling Claude
  Design to ask.
- Keep **`{{FLOWS}}` / `{{VIEWPORTS}}`** factual from the manifest.
