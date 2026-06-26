# hermes-test

Scratch repo for testing [Hermes](https://www.agent37.com/) on Agent 37.

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
