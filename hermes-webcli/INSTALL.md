# Hermes web-cli toolkit (installed on instance ym8dpjcfhi)

Reference copy of the browser-profiles + credential toolkit that lives on the
Agent37 instance at `/home/node/web-cli/`, plus the Hermes skill that teaches the
agent to use it (`~/.hermes/skills/web-cli/SKILL.md`).

## What's on the instance
- `/home/node/web-cli/lib/profiles.py` — `browser()` (Patchright + bundled Chromium,
  5 persistent profiles, auto-fallback, Xvfb :99). Browsers in
  `/home/node/web-cli/.ms-playwright` (the entrypoint's `/opt/ms-playwright` is read-only).
- `/home/node/web-cli/lib/creds.py` — `get/put/totp` credential + 2FA store.
- `~/.hermes/skills/web-cli/SKILL.md` — teaches Hermes the concept (verified: `hermes skills list` shows it enabled).

## Verified
- `pip install patchright` + `patchright install chromium` → `/home/node/web-cli/.ms-playwright`.
- `browser()` launches, loads example.com, screenshots (17 KB PNG). ✓
- `creds.put/get` + `creds.totp` (6-digit codes). ✓
- Reaches real signup forms (Instagram emailsignup loaded fully). ✓

## Account creation — capability present, autonomous completion BLOCKED
Google/Instagram/Facebook gate new accounts behind **SMS phone verification +
CAPTCHA + datacenter-IP reputation**. The toolkit drives the browser to the signup
form, but completion walls at verification. To actually create such accounts you
need: per-site signup selectors + an SMS-verification service + a residential proxy.
Attempting Google signup in profile1 would also risk the working Tenderwright
Google session (Calendar/Slack) — use throwaway profiles only.
