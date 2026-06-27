# Hermes on Agent37 — full setup (replicate / share / version)

Everything needed to stand up a Hermes agent on an [Agent37](https://agent37.com)
instance, talk to it via Slack, and run inference on a **Claude Max subscription
(OAuth)** instead of an API key — with the hard-won fixes baked in.

> Read [`GOTCHAS.md`](./GOTCHAS.md) too — it's the why behind every step here.
> The Slack stack is **Hermes** (Nous Research), not Agent37; Agent37 only hosts
> the box + a managed model proxy.

## Artifacts in this folder
| File | What it is |
|---|---|
| `config.yaml.template` | `~/.hermes/config.yaml` — providers + default model (secrets templated) |
| `hooks/post-restart.sh.template` | `~/.agent37/hooks/post-restart.sh` — re-asserts the subscription every boot |
| `hooks/post-image-update.sh.template` | `~/.agent37/hooks/post-image-update.sh` — re-applies lib patches on image change |
| `patches/oauth-system-relocate.py` | lib patch: keeps OAuth requests in the **plan** lane (not "extra usage") |
| `patches/slack-bang-cmd-fix.py` | lib patch: fixes `!command <args>` arg-corruption in Slack |
| `skills/slack-integration.SKILL.md` | corrected skill (Slack uses `!`; 4-6/4-8 are real) |
| `GOTCHAS.md` | every trap we hit + the proof |

Tools live one level up: `../a37` (exec wrapper), `../hermes-sub` (subscription
toggle), `../slack/manifest.json` (Slack app), `../pull-logs.sh`.

`<<PLACEHOLDERS>>` mark secrets — never commit the filled-in versions.

## Prerequrisites
- An Agent37 workspace API key (`sk_live_…`) — treat like root; per-purpose, revocable.
- The `claude` CLI locally (`npm i -g @anthropic-ai/claude-code`) for `setup-token`.
- A Claude **Max** subscription (the OAuth path bills against the plan, not extra usage).

## Steps

### 1. Point the tooling at your instance
```bash
export AGENT37_KEY=sk_live_...          # your workspace key
export AGENT37_INSTANCE=<instanceId>    # 10-char id; create one in the dashboard or API
../a37 info                             # sanity check: status=running
```

### 2. Slack channel (Hermes "channel", not a tool)
1. Create a **dedicated** Slack app from `../slack/manifest.json` (Socket Mode).
   Use a separate app from any Composio/tool bot (one Events URL per app).
2. Copy the app-level `xapp-…` and bot `xoxb-…` tokens onto the instance:
   ```bash
   ../a37 "printf 'SLACK_BOT_TOKEN=xoxb-...\nSLACK_APP_TOKEN=xapp-...\n' >> ~/.hermes/.env && chmod 600 ~/.hermes/.env"
   ```
3. Pair yourself: DM the bot, then approve on the instance:
   `../a37 'hermes pairing approve slack <code>'`.

### 3. Install the lib patches (the box's lib is on an ephemeral overlay)
```bash
../a37 'mkdir -p /home/node/.agent37/patches'
for p in patches/*.py; do
  B64=$(base64 < "$p" | tr -d '\n')
  ../a37 "echo $B64 | base64 -d > /home/node/.agent37/patches/$(basename $p)"
done
```
The hooks (next step) re-run every `patches/*.py` on each boot / image update, so
they survive Agent37 wiping the overlay.

### 4. Turn on the Claude Max subscription
```bash
claude setup-token                                   # browser login -> sk-ant-oat01-...
export GIO_CLAUDE_SETUP_TOKEN_1YR=sk-ant-oat01-...   # the token it printed
../hermes-sub enable "$GIO_CLAUDE_SETUP_TOKEN_1YR"   # writes .env, model, zhiyun fallback, post-restart hook
../hermes-sub status                                 # expect: SUBSCRIPTION (OAuth), is_oauth True
```
`hermes-sub` also wires `post-restart.sh` to re-assert the token + model + patches
every boot. Add `post-image-update.sh` (re-applies patches on image change):
```bash
B64=$(base64 < hooks/post-image-update.sh.template | tr -d '\n')   # fill placeholders first if you customized it
../a37 "echo $B64 | base64 -d > /home/node/.agent37/hooks/post-image-update.sh && chmod +x /home/node/.agent37/hooks/post-image-update.sh"
```

### 5. Corrected Slack skill (stops the model-name hallucination loop)
```bash
DST=/home/node/.hermes/skills/social-media/slack-integration/SKILL.md
B64=$(base64 < skills/slack-integration.SKILL.md | tr -d '\n')
../a37 "mkdir -p $(dirname $DST) && echo $B64 | base64 -d > $DST"
../a37 'hermes curator pin slack-integration'        # stop self-improvement re-corrupting it
```

### 6. Restart the gateway + verify
```bash
../a37 'pkill -f "hermes gateway run" || true'        # supervisor respawns it with the new env
sleep 8
../hermes-sub status
```
In Slack, switch models by chat (Slack eats `/`, so use **`!`**):
```
!model claude-opus-4-8   --provider anthropic     # subscription, opus
!model claude-sonnet-4-6 --provider anthropic     # subscription, sonnet
!model claude-sonnet-4-5-20250929 --provider custom:zhiyun   # API-key fallback
!new                                              # fresh session on the default
```
To check the live model, use `!model` — **not** "what model are you" (the LLM
hallucinates its own ID; see GOTCHAS.md).

## Verifying it really bills the plan (not "extra usage")
A real OAuth `/v1/messages` call returns `anthropic-ratelimit-unified-status:
allowed` with `unified-5h-utilization` incrementing. `service_tier: standard`
does **not** prove this. If you ever get HTTP 400 "out of extra usage", check the
plan window isn't exhausted and that `patches/oauth-system-relocate.py` is applied
(see GOTCHAS.md → "Why the gateway hit extra-usage").

## Security
- Never commit a filled-in `.env`, `config.yaml`, or hook — they hold the OAuth
  setup token + provider API keys. Keep `<<PLACEHOLDERS>>` in git.
- The `sk_live_` Agent37 key = full file/exec access to the whole workspace fleet.
- The OAuth setup token sits on the box; Agent37 operators can read instance files.
  Use a dedicated `claude setup-token` (separate refresh lineage from your laptop login).
