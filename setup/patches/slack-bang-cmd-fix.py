#!/usr/bin/env python3
# Idempotent patch: the Slack adapter rewrites a leading "!cmd" -> "/cmd" BEFORE
# merging rich_text block text. The block copy still reads "!cmd ...", so the
# dedup ("not in text") thinks it's new and appends it -> "/model X\n!model X" ->
# command args contain a newline/space -> "Model names cannot contain spaces".
# Fix: skip the block-text append for command messages (text already starts "/").
# Lib is on the ephemeral overlay; re-applied by post-restart/post-image hooks.
import pathlib, sys
f = pathlib.Path("/usr/local/lib/hermes/hermes-agent/gateway/platforms/slack.py")
s = f.read_text()
if "BANG_CMD_FIX" in s:
    print("cmd-fix already applied"); sys.exit(0)
old = "                if stripped_blocks and stripped_blocks not in text.strip():"
new = ("                # BANG_CMD_FIX: don't re-append block-extracted text for a\n"
       "                # command message — the rewritten \"/cmd\" vs the block copy\n"
       "                # \"!cmd\" always mismatches and would corrupt the command args.\n"
       "                if stripped_blocks and stripped_blocks not in text.strip() and not text.lstrip().startswith(\"/\"):")
assert old in s, "anchor not found"
assert s.count(old) == 1, "anchor not unique"
f.write_text(s.replace(old, new))
import ast; ast.parse(f.read_text())
print("cmd-fix applied + syntax OK")
