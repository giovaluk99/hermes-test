# Agent37 / Hermes — how it runs under the hood

Notes from poking at a live instance (`ym8dpjcfhi`, template `agent37-hermes`,
2 vCPU / 4 GB / 6 GB) via the `exec` endpoint. Everything below is observed, not
guessed — commands are reproducible with the `./a37` wrapper in this repo.

## 1. The request path: two planes

```
your curl ──▶ api.agent37.com/v1        (Hosting API: create/list/delete/exec/templates/budgets)
              └─ authenticates key, selects workspace, manages the fleet

your curl ──▶ {id}.agent37.app          (Agent API: the instance's own gateway)
              └─ platform edge authenticates the same sk_live_ key,
                 verifies the instance is in your workspace,
                 forwards to the gateway running *inside* the instance
```

One `sk_live_` key works on both. The instance id (`ym8dpjcfhi`) doubles as the
DNS label. Every port the template declares gets a URL:

| Port | URL | Process inside |
|------|-----|----------------|
| 3737 (default) | `{id}.agent37.app` | `agent37-gateway` (the chat API: `/v1/responses` etc.) |
| 9119 | `{id}-9119.agent37.app` | dashboard relay (Node) → Hermes dashboard on `127.0.0.1:19119` |
| 7681 | `{id}-7681.agent37.app` | `ttyd` — the in-browser terminal |
| 8080 | `{id}-8080.agent37.app` | `filebrowser` (`--noauth`, fronted by the edge auth) |

There is no SSH daemon. "Shelling in" = `POST /v1/instances/{id}/exec`, which runs
your string under `sh -c` and returns `{exit_code, stdout, stderr, truncated}`.
Each exec is a **fresh, stateless `sh -c`** — no `cd`/env carries between calls
(chain with `&&` in one command if you need state). Caps: 512 KB per stream,
280 s wall-clock.

## 2. What's actually running

PID 1 is `entrypoint.sh` (a bash script, *not* an init system), which fans out to:

- `Xvfb :99` + `openbox` — a headless X display, so the agent can drive a real
  browser / GUI apps (`DISPLAY=:99`).
- `hermes gateway run` (Python venv) — the Hermes agent runtime.
- `hermes dashboard` (Python) on localhost:19119 + a Node `dashboard-relay.js`.
- `agent37-gateway` (Node) on `:3737` + a `hermes_worker.py` — the API the
  outside world talks to.
- `ttyd` on `:7681`, `filebrowser` on `:8080`.

Managed creds are injected as env vars on the processes (Brave/Composio proxy
tokens, a `AGENT37_STARTER_TOKEN`) — this is how "managed LLM / search / tools"
work with no keys of your own. Bring-your-own keys bypass that meter.

Runs as unprivileged user **`node`** (uid 1000), **zero effective capabilities**
(`CapEff: 0000000000000000`).

## 3. The sandbox: gVisor, not a VM, not plain Docker

Hard evidence it's [gVisor](https://gvisor.dev) (`runsc`):

- `uname -r` → `4.19.0-gvisor` (gVisor reports a synthetic kernel version).
- `dmesg` → `Starting gVisor...` / `Generating random numbers by fair dice roll...`
  (gVisor's joke boot log).
- `/proc/cpuinfo` `model name : unknown` — gVisor doesn't pass through host CPU ID.
- Root is `overlay`; everything else (`/proc`, `/sys`, `/dev`) is served by the
  **Sentry**, gVisor's userspace kernel.

gVisor is a **userspace kernel**: a process (`runsc`) written in Go that
implements the Linux syscall surface itself. Your container's syscalls hit the
Sentry, *not* the host kernel directly. So it's stronger isolation than a normal
container (the host kernel is not directly reachable) but lighter than a VM (no
guest kernel, no hardware virtualization).

```
  true VM:    app → guest kernel → hypervisor (KVM) → host kernel → hardware
  gVisor:     app → runsc Sentry (userspace "kernel") → ~limited host syscalls → host kernel
  plain ctr:  app → host kernel (shared)
```

## 4. Filesystem & persistence

| Path | Mount | Lifetime |
|------|-------|----------|
| `/` | `overlay` (8 EB sparse, ~28 MB used) | **ephemeral** — image layer + writable scratch, reset on rebuild/migrate |
| `/home/node` | `9p` (`directfs`), shows the **6 GB disk** you bought | **persistent** — files, connected accounts, agent memory survive stop/start |
| `/home/linuxbrew`, `/etc/hosts`, `/etc/resolv.conf`, `/etc/hostname` | `9p` | host-managed, persistent |
| `/tmp`, rest of `/` | overlay | ephemeral |

The persistent volume is a **9p network filesystem** (the gVisor gofer process on
the host serves files to the sandbox), not a local block device. Practical
upshot: put anything you care about under `/home/node`; treat the rest as scratch.
`df` shows `/home/node` = 6.0 GB, matching `resources.disk: 6` at create.

## 5. Resource enforcement

Plain Linux cgroups, enforced by the host (gVisor honors them):

- `cpu.cfs_quota_us = 200000` (period 100000) → **2 vCPU**, matches `nproc`.
- `memory.limit_in_bytes = 4294967296` → **4 GiB**.
- disk = the 9p volume size (6 GB).

These are the `resources` you set on create; resizing re-debits at the new size.

Network egress is open (`curl https://ifconfig.me` → 200), but there's **no raw
socket** (`ping`/ICMP unavailable) — gVisor only exposes TCP/UDP via its netstack.

## 5b. Headful browsers & residential proxies

**Headful browsers: yes.** `chromium` is at `/usr/bin/chromium`, plus a Playwright
build at `/opt/ms-playwright/chromium-1228/`. The entrypoint runs `Xvfb :99` +
`openbox`, so a real browser with full UI renders to the virtual framebuffer
(viewable via the live desktop / ttyd on :7681). Launching `chromium` **without**
`--headless` against `DISPLAY=:99` produced a real window (tab strip, address bar,
the `--no-sandbox` infobar) — see [img/headful-chromium.png](img/headful-chromium.png).

```bash
./a37 'export DISPLAY=:99; chromium --no-sandbox --window-size=1280,800 https://example.com & \
       sleep 6; import -window root /tmp/shot.png'   # imagemagick is preinstalled
```

Notes: pass `--no-sandbox` (Chrome's own sandbox can't nest inside gVisor as uid
1000); the `dbus`/GCM errors in the log are harmless. The exec shell has an empty
`DISPLAY`, so set `DISPLAY=:99` yourself.

**Residential IP proxy — the instance is NOT residential.** Egress is a datacenter
IP: `15.204.212.224`, **AS16276 OVH SAS** (Virginia). You can't make the instance
itself a residential exit. Two things follow:

- **Route through a 3rd-party residential proxy: works.** Both paths verified:
  - Per-app HTTP(S): `HTTPS_PROXY=http://user:pass@gw.provider:port` (curl/Node/
    Python honor it). A test against a bogus proxy made curl time out *on the
    proxy* instead of going direct — proof traffic is routed through it.
  - Chromium: `--proxy-server="http://user:pass@gw.provider:port"` (or SOCKS5).
    Accepted and launches. Use a provider like Bright Data / Oxylabs / IPRoyal /
    Smartproxy; supply your own creds (these go straight out, never touch the
    managed meter).
  - For apps that ignore proxy env, `proxychains` (LD_PRELOAD, **no privileges
    needed**) can wrap them — not preinstalled, but installable via the bundled
    linuxbrew or pip/npm into `/home/node`.
- **System-wide VPN/tun: no.** `/dev/net/tun` exists, but `CapEff` is empty (no
  `CAP_NET_ADMIN`), so you can't bring up a `tun` device — OpenVPN/WireGuard at
  the OS level won't work. Per-app proxying is the supported pattern. (This is
  the same capability limit covered below.)

## 6. gVisor limitations vs a true VM

What you give up by being in a gVisor sandbox instead of a full VM:

**Can't do at all (by design):**
- **No nested virtualization** — `/dev/kvm` absent. You can't run VMs, Firecracker,
  or anything needing hardware virt inside the instance.
- **No kernel modules** — `lsmod`/`modprobe` gone, `/lib/modules` empty. No custom
  kernel modules, eBPF programs, or out-of-tree drivers.
- **No raw/packet sockets** — no ICMP `ping`, no `tcpdump`/raw packet capture,
  no custom L2/L3 networking. Only TCP/UDP through gVisor's userspace netstack.
- **No privileged operations** — uid 1000 with empty capability set: no `mount`,
  no `iptables`, no `sysctl` writes, no device creation, no `setuid` root tricks.
- **No real `/dev`** — only a curated set (null, zero, random, urandom, fuse, net,
  pts…). No block devices, no `/dev/kvm`, no GPU passthrough (`/dev/dri` absent).

**Works but differently / with overhead:**
- **Syscall compatibility is a subset.** gVisor implements *most* of the Linux
  ABI, but not 100%. Obscure or very new syscalls, exotic `ioctl`s, and some
  `/proc` and `/sys` files are stubbed, faked (`model name: unknown`), or return
  `ENOSYS`. Mainstream software (Python, Node, browsers, Hermes) runs fine;
  low-level/kernel-adjacent tooling may not.
- **Syscall-heavy workloads are slower.** Every syscall is intercepted and
  handled in the Go Sentry instead of falling straight through to the host
  kernel. CPU-bound work in userspace is ~native; syscall-bound work (lots of
  small I/O, fork/exec storms, tight network round-trips) pays an interception
  tax a VM doesn't.
- **Filesystem is 9p, not a local disk.** Metadata-heavy operations (millions of
  tiny files, `git` on huge trees) are slower than a real block device, and
  semantics around mmap/locking can differ from a native FS.
- **`ptrace`/perf is limited.** `strace`, native profilers, debuggers that rely on
  `ptrace` or perf counters are partly or fully unavailable, so deep debugging of
  processes inside the sandbox is constrained.
- **A synthetic kernel.** Tools that sniff the host kernel version, CPU model, or
  hardware (some installers, GPU libs, licensing checks) see gVisor's stand-ins,
  not the real host.

**What you gain in exchange:** much stronger isolation than a shared-kernel
container (a kernel exploit has to get through the Go Sentry first, then still
faces a restricted host syscall set), with far faster startup and lower overhead
than booting a real VM per tenant. For an "always-on computer per end user"
that's the right trade — it just means the instance is a place to run *agents and
apps*, not a place to run *kernels, VMs, or privileged infra*.

## 7. Logs & observability

There is **no logs endpoint** on either plane. `dmesg`/journald don't apply
(PID 1 is `entrypoint.sh`, not an init system), and process stdout goes to the
*host's* container log (`/proc/1/fd/1 -> host:[2]`) which you can't read from
inside. You assemble log pulling from three exposed sources:

| Want | Source | How |
|------|--------|-----|
| Runtime / system logs | files in `~/.hermes/logs/` (`agent.log`, `errors.log`, `gateway.log`, `gui.log`, `gateway-exit-diag.log`) | `GET {id}.agent37.app/v1/files/content?path=...` (no 512 KB cap) |
| Quick tail / grep | same files | `exec 'tail -n 200 ~/.hermes/logs/agent.log'` (512 KB cap) |
| Discover what log files exist | the instance | `exec 'find ~/.hermes/logs -type f'` |
| Agent conversation logs | the gateway | `GET {id}.agent37.app/v1/sessions`, then `/v1/responses/{id}` |
| Live agent activity (reasoning/tools/output) | a running turn | `stream: true` on `/v1/responses`, or replay+attach via `/v1/responses/{id}/stream` |

(OpenClaw instances keep logs under a different dir — set `AGENT37_LOG_SRC`.)

**Setup:** [`pull-logs.sh`](../pull-logs.sh) mirrors every instance in the
workspace into `logs/<id>/` — it lists instances on the hosting API, `find`s the
log files via `exec`, pulls each uncapped via the Files endpoint, and grabs
`/v1/sessions`. Run it from cron/launchd for continuous pulling (each run
overwrites with the instance's current full file = always-latest mirror).
Verified live: pulled 5 log files + sessions from `ym8dpjcfhi` in one run.

For large/growing logs, switch the whole-file pull to an incremental byte-offset
tail (`exec 'tail -c +$N file'`, track `$N` locally). For a real pipeline, point
the pull at your log store (Loki/CloudWatch/S3) instead of local files.

---

### Reproduce

```bash
export AGENT37_KEY=sk_live_...        # or rely on AGENT37_GIO_TEST
export AGENT37_INSTANCE=ym8dpjcfhi
./a37 info                            # instance object
./a37 'uname -a; cat /proc/1/comm'    # one-off command
./a37 'dmesg | head'                  # the gVisor boot banner
./a37 repl                            # pseudo-shell (each line = one stateless exec)
```
