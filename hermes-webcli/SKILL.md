---
name: web-cli
description: Browse the real web with a normal fingerprint and stay logged in across sessions, and manage your own login credentials/2FA. Use when you need to log into a site, keep a persistent browser session, sign up for an account, or do anything requiring a real Chrome browser. Toolkit lives at /home/node/web-cli.
metadata:
  author: gio
  version: "1.0.0"
---

# web-cli — browser profiles + credential store

A toolkit at **/home/node/web-cli** that lets you drive a real Chromium browser
(Patchright, stealthed, normal fingerprint) with **persistent profiles** (logins
survive), plus a **credential/2FA store**. Headful runs on the existing Xvfb `:99`.

## Concept
- **Profiles** = 5 persistent Chrome user-data dirs (`profiles/profile1..5`). A
  session grabs the first free one (lock files prevent collisions). Once you log
  into a site in a profile, that login **persists** — next time you reuse it, no
  re-login.
- **Credential store** = `credentials.json` (chmod 600). `get/put/totp`. When you
  **create a new account**, save it here so it's reusable.

## Use it (Python, in the instance)
```python
import sys; sys.path.insert(0, "/home/node/web-cli")
from lib.profiles import browser
from lib import creds

# drive a browser (headless=False to render on the desktop :99)
with browser(headless=True) as ctx:
    page = ctx.new_page()
    page.goto("https://example.com", wait_until="domcontentloaded")
    page.screenshot(path="/tmp/shot.png")

# stored creds + 2FA
c = creds.get("gmail")          # {"username","password","totp_secret",...} or None
code = creds.totp("gmail")      # current 6-digit TOTP, if totp_secret stored
```
Run with the venv: `/home/node/.venv/bin/python your_script.py`.

## Creating accounts (save them!)
When you sign up for a new service, after success:
```python
creds.put("instagram", {"username": "...", "password": "...", "totp_secret": "...", "email": "..."})
```
Then future logins use `creds.get("instagram")` + `creds.totp("instagram")` and the
profile keeps the session.

## Gotchas (real)
- **Signup verification walls:** Google/Meta (Instagram/Facebook) gate new accounts
  behind **SMS phone verification, CAPTCHAs, and IP/device reputation**. This
  instance's egress is a flagged datacenter IP — expect signups to stall at phone
  verification. To actually create such accounts you need a phone/SMS-verification
  service and ideally a residential proxy (route via `HTTPS_PROXY` or Chromium
  `--proxy-server`). Don't assume blind signup will succeed; report where it walls.
- **Headful for stealth:** some sites detect headless. Use `headless=False` (renders
  to `:99`) for anti-bot sites; screenshot to inspect.
- **One profile per identity:** keep each account in its own profile to avoid
  cross-contaminating logged-in sessions.
- **Patchright browser path** is pinned to `/home/node/web-cli/.ms-playwright`
  (the entrypoint's `/opt/ms-playwright` is read-only).

See `/home/node/web-cli/README.md` for more.
