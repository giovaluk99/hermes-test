"""Browser profiles with auto-fallback (Patchright + bundled Chromium).

5 persistent Chrome user-data dirs under profiles/profile1..5. A session grabs
the first un-locked profile (lock files coordinate across concurrent agents);
locks older than 2h are reclaimed. Logged-in sessions persist in the profile.

    from lib.profiles import browser
    with browser(headless=True) as ctx:        # auto-picks first free profile
        page = ctx.new_page(); page.goto("https://example.com")
"""
import os, time, contextlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROFILES = ROOT / "profiles"
LOCK_TTL = 2 * 3600
# MUST be set before patchright import: /opt/ms-playwright (entrypoint default)
# is root-owned/read-only, so use a writable, persistent path.
os.environ["PLAYWRIGHT_BROWSERS_PATH"] = str(ROOT / ".ms-playwright")
os.environ.setdefault("DISPLAY", ":99")

def _free_profile(preferred=None):
    PROFILES.mkdir(exist_ok=True)
    order = ([preferred] if preferred else []) + [i for i in range(1, 6) if i != preferred]
    for i in order:
        lock = PROFILES / f"profile{i}.lock"
        if lock.exists() and (time.time() - lock.stat().st_mtime) < LOCK_TTL:
            continue
        lock.write_text(str(os.getpid()))
        return i, lock
    raise RuntimeError("no free browser profile (all 5 locked)")

@contextlib.contextmanager
def browser(headless=True, preferred=None):
    from patchright.sync_api import sync_playwright
    i, lock = _free_profile(preferred)
    try:
        udd = PROFILES / f"profile{i}"; udd.mkdir(exist_ok=True)
        with sync_playwright() as p:
            ctx = p.chromium.launch_persistent_context(
                str(udd), headless=headless,
                args=["--no-sandbox", "--disable-dev-shm-usage",
                      "--disable-blink-features=AutomationControlled"],
                viewport={"width": 1280, "height": 800},
            )
            try:
                yield ctx
            finally:
                with contextlib.suppress(Exception): ctx.close()
    finally:
        with contextlib.suppress(Exception): lock.unlink()  # always release
