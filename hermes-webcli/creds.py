"""Credential + TOTP store (credentials.json, chmod 600, git-ignored).

    from lib import creds
    c = creds.get("gmail"); c["username"], c["password"]
    code = creds.totp("gmail")              # 6-digit 2FA if totp_secret stored
    creds.put("instagram", {"username":..., "password":..., "totp_secret":...})
"""
import json, hmac, hashlib, struct, time, base64
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "credentials.json"

def _load():
    if not STORE.exists(): return {}
    return json.loads(STORE.read_text())

def get(site): return _load().get(site)

def put(site, data):
    d = _load(); d[site] = data
    STORE.write_text(json.dumps(d, indent=2)); STORE.chmod(0o600)
    return data

def totp(site, digits=6, period=30):
    c = get(site) or {}
    secret = c.get("totp_secret")
    if not secret: return None
    key = base64.b32decode(secret.replace(" ", "").upper() + "=" * (-len(secret) % 8))
    msg = struct.pack(">Q", int(time.time()) // period)
    h = hmac.new(key, msg, hashlib.sha1).digest()
    o = h[-1] & 0x0F
    code = (struct.unpack(">I", h[o:o+4])[0] & 0x7FFFFFFF) % (10 ** digits)
    return str(code).zfill(digits)
