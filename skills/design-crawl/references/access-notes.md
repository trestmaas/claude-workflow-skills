# Access notes — authenticating a crawl

Two failure modes will silently waste time. Both were learned the hard way.

## 1. Chrome ≥136 refuses remote debugging on the default profile

Importing the user's existing logged-in session by launching their everyday
Chrome with `--remote-debugging-port` **does not work on Chrome 136+ (April
2025).** The flag is accepted and silently ignored — no port opens, no error.
It was added as a security fix precisely to stop tools from attaching to a real
profile and reading its cookies.

Symptoms you'll see if you try: `curl localhost:9222/json/version` never
responds; the Chrome process shows the flag but binds no port. Don't debug it —
it's by design.

Also: if the user's Chrome is **already running**, a second launch just hands
the URL to the existing process and drops the flag. And a sandboxed shell often
can't `kill` Chrome or reach `localhost` — quitting must happen from the macOS
UI (⌘Q), not through the agent.

**Do this instead:** sign in inside the automation tool's *own* browser profile
(e.g. `agent-browser --session <persona> --headed open <sign-in-url>`), which
allows CDP because it's not the default profile. Save the state
(`agent-browser --session <persona> state save <path-outside-repo>`) and reuse
it. Verify a real auth cookie is present — not just an analytics cookie — before
declaring success.

## 2. Google (and most) SSO refuses automated browsers

"Sign in with Google" inside a CDP-controlled browser lands on
`accounts.google.com/.../rejected` — *"This browser or app may not be secure."*
Google detects automation and refuses OAuth. Do not try to defeat the detection.

**Do this instead:** use the app's **email + password** path into the automation
session. If the account is SSO-only, have the user set a password first (a
password-reset link), or use a throwaway account provisioned for the crawl.

## 3. Keep the crawl session isolated from the user's data

- Use a **named isolated session per persona** (`--session anon`, `--session
  admin`) so personas don't cross-contaminate and the crawl never touches the
  user's real logged-in browser.
- Verify anonymity/identity early: snapshot the top nav and confirm you're the
  persona you intend to be (avatar present vs. "Sign in") before walking.
- **Never write auth state into the repo.** Save it to a scratch dir outside any
  git working tree, `chmod 600`. If a tool writes it into the repo by default,
  move it out immediately.

## 4. Mutation safety on production

If the user approves real writes, use **plus-addressed emails**
(`owner+crawl1@gmail.com`) so confirmation mail reaches their own inbox. Leave
optional phone/SMS fields blank. Never confirm an irreversible action
(delete/cancel/pay/send) without explicit per-action approval — screenshot the
confirm dialog and press Escape. Record every signup/record you create in the
manifest `method` or a "state left behind" note so the user can clean up.
