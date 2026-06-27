# hermes-test

Working repo for running [Hermes](https://www.agent37.com/) on Agent37 — including
our full **Claude Max subscription (OAuth)** setup, Slack channel, lib patches, and
the hard-won gotchas.

## ▶ Replicating the whole setup
See **[`setup/SETUP.md`](setup/SETUP.md)** for the end-to-end guide (instance, Slack,
subscription, patches, skill) and **[`setup/GOTCHAS.md`](setup/GOTCHAS.md)** for the
why behind each step. Secrets are templated as `<<PLACEHOLDERS>>` — never commit
filled-in copies. `setup/` artifacts:
- `patches/` — lib patches (keep OAuth in the plan lane; fix Slack `!command` args)
- `hooks/` — boot hooks that re-assert the subscription + re-apply patches
- `config.yaml.template`, `skills/slack-integration.SKILL.md`
- `../hermes-sub` — one-command subscription enable/status toggle

## Try it
Ask Hermes to:
- read this README and summarize it
- add a file and open a PR
- run `python hello.py`

## Poking at the instance

`./a37` is a tiny wrapper over the Agent37 `exec` endpoint (needs `jq` + `curl`):

```bash
export AGENT37_KEY=sk_live_...   # or rely on AGENT37_GIO_TEST in env
export AGENT37_INSTANCE=ym8dpjcfhi
./a37 'uname -a'     # run a command   ./a37 info   # instance object   ./a37 repl
```

See [docs/under-the-hood.md](docs/under-the-hood.md) for how the instance runs
(two-plane API, process tree, the gVisor sandbox, persistence, and gVisor-vs-VM limits).

## Pulling instance logs

`./pull-logs.sh` mirrors every instance's logs into `logs/<id>/` (git-ignored).

```bash
export AGENT37_KEY=sk_live_...        # or rely on AGENT37_GIO_TEST
./pull-logs.sh                        # one-shot pull of the whole workspace
# continuous: cron every 5 min
*/5 * * * * cd /path/to/hermes-test && AGENT37_KEY=sk_live_... ./pull-logs.sh >> logs/pull.cron.log 2>&1
```

Sources stitched (there's no logs endpoint): runtime log files via the Files
endpoint, file discovery via `exec`, conversation history via `/v1/sessions`.
See [docs/under-the-hood.md](docs/under-the-hood.md#7-logs--observability).

## Chatting with the Hermes agent

`./a37 chat '<message>'` talks to the agent on the instance (Agent API,
`POST /v1/responses`) and keeps the conversation in `.a37-session.<id>` (git-ignored).
Google Calendar is connected (as `tenderwright@gmail.com` via Composio OAuth), so you
can ask it to schedule meetings:

```bash
./a37 chat "Schedule a 30-min meeting with andi@example.com and sally@example.com
            Tuesday 2pm PT titled 'Sync', add a Google Meet link and invite them."
```
