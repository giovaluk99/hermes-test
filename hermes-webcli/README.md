# web-cli (in-instance) — browser profiles + credential store for Hermes

Lets Hermes browse the real web with a normal fingerprint and stay logged in.

- **lib/profiles.py** — `browser()`: Patchright + system Chromium, 5 persistent
  profiles with auto-fallback. Headful runs on Xvfb `:99`.
- **lib/creds.py** — `get/put/totp`: credential + 2FA store in `credentials.json`
  (chmod 600). Save accounts you create here.
- **profiles/** — persistent Chrome user-data dirs (logins persist).

## Use
```python
import sys; sys.path.insert(0, "/home/node/web-cli")
from lib.profiles import browser
from lib import creds
with browser(headless=True) as ctx:
    page = ctx.new_page(); page.goto("https://example.com")
    page.screenshot(path="/tmp/shot.png")
```
Create an account → `creds.put("<site>", {"username":..,"password":..,"totp_secret":..})`.
