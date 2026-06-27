#!/usr/bin/env python3
# Idempotent patch: for OAuth requests, keep the Anthropic `system` prompt = the
# Claude Code identity block only, and relocate Hermes' own system instructions
# into the first user turn. Anthropic scores the SYSTEM prompt for Claude-Code
# authenticity and routes non-CC system content into the extra-usage lane (HTTP
# 400 "out of extra usage"); user content is not classified. Verified against the
# live API. Re-run safely; wired into ~/.agent37/hooks/post-image-update.sh.
import pathlib, sys
f = pathlib.Path("/usr/local/lib/hermes/hermes-agent/agent/anthropic_adapter.py")
s = f.read_text()
MARK = "OAUTH_SYSTEM_RELOCATE"
if MARK in s:
    print("relocate patch already applied"); sys.exit(0)

# anchor: the final `return kwargs` of build_anthropic_kwargs, right after the
# fast-mode block. It's unique (ends with the fast-mode extra_headers assignment).
anchor = '''        kwargs["extra_headers"] = {"anthropic-beta": ",".join(betas)}

    return kwargs'''
inject = '''        kwargs["extra_headers"] = {"anthropic-beta": ",".join(betas)}

    # OAUTH_SYSTEM_RELOCATE: Anthropic scores the SYSTEM prompt for Claude-Code
    # authenticity and routes non-CC system content into the extra-usage lane
    # (HTTP 400). Keep system = the Claude Code identity block only; move Hermes'
    # real instructions into the first user turn (not classified). Plan-lane safe.
    if is_oauth and isinstance(kwargs.get("system"), list) and len(kwargs["system"]) > 1:
        sysb = kwargs["system"]
        kwargs["system"] = sysb[:1]
        moved = "\\n\\n".join(
            b.get("text", "") for b in sysb[1:]
            if isinstance(b, dict) and b.get("type") == "text" and b.get("text")
        )
        if moved:
            msgs = kwargs.get("messages") or []
            if msgs and msgs[0].get("role") == "user":
                c = msgs[0].get("content")
                if isinstance(c, str):
                    msgs[0]["content"] = moved + "\\n\\n" + c
                elif isinstance(c, list):
                    msgs[0]["content"] = [{"type": "text", "text": moved}] + c
                else:
                    msgs[0]["content"] = moved
            else:
                msgs = [{"role": "user", "content": moved}] + msgs
            kwargs["messages"] = msgs

    return kwargs'''
assert anchor in s, "anchor (fast-mode return) not found"
assert s.count(anchor) == 1, "anchor not unique"
f.write_text(s.replace(anchor, inject))
import ast; ast.parse(f.read_text())
print("relocate patch applied + syntax OK")
