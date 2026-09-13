# manifest.json schema

Machine-readable index of a design crawl. Consumed by `crawl-visualizer.html`
and by the Claude Design handoff prompt. Keep categories **emergent** — the
`observations` and `inconsistencies` fields are free-form; do not constrain them
to a preset taxonomy.

## Shape

```jsonc
{
  "app": "string — product name",
  "url": "string — base URL crawled",
  "captured": "YYYY-MM-DD",
  "method": "string — how it was crawled: personas, sessions, auth, mutation policy, anything needed to reproduce",
  "personas": [
    { "id": "anon", "label": "Anonymous visitor", "job": "one line: what this persona is trying to do" }
  ],
  "flows": ["onboarding", "checkout", "settings"],   // the journeys walked
  "viewports": { "mobile": "390x844", "desktop": "1280x720" },

  "screens": [
    {
      "file": "screens/m-03-checkout-review.png",     // relative to the zip root
      "viewport": "390x844 (mobile)",
      "persona": "anon",                               // persona id, or null
      "flow": "checkout",
      "step": "review",                                // short slug for the step
      "job": "confirm the order",                      // verb phrase, what the user does here
      "surface": "full-page",                          // full-page | modal | drawer | sheet | popover | dropdown | inline | tab | toast | none
      "observations": [                                // FREE-FORM. What you actually noticed. Empty [] if clean.
        "The primary CTA and the destructive 'Cancel order' are the same weight and color.",
        "Email wraps mid-token on this width."
      ],
      "severity": "high"                               // blocker | high | medium | low | note   (omit if no observation)
    }
  ],

  "inconsistencies": [                                 // EMERGENT clusters — same underlying problem seen across screens
    {
      "summary": "one line naming the pattern, in the app's own terms",
      "severity": "high",
      "evidence": ["screens/m-03-...png", "screens/d-05-...png"]   // the screens that show it
    }
  ],

  "gaps": [                                            // honest limits of this crawl
    "Desktop only for the admin persona — mobile not run.",
    "Thin data: 1–2 records per list; problems that only bite at scale not observable."
  ]
}
```

## Rules

- **`file` paths are relative to the zip root** so the visualizer and README
  resolve them the same way.
- **Every screen is listed**, even clean ones (empty `observations`) — the
  visualizer needs the full set to show a complete walk.
- **`severity` is by user impact, not effort.** blocker = can't finish the task;
  high = confusing or error-inducing; medium/low = friction; note = neutral
  observation worth surfacing.
- **`inconsistencies` are conclusions; `observations` are raw sightings.** A
  cluster references the screens whose observations it generalizes. Do not invent
  a cluster with no screen evidence.
- **Neutral language.** Describe what is on screen, not the fix. "Two confirm
  dialogs use opposite button colors" — not "should standardize on destructive-red".
