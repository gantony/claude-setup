# claude-setup

Run Claude Code in a rootless [Podman](https://podman.io/) container, so the
**container is the boundary**: only `~/github` (plus this repo's `kube/`) is
mounted, the rest of your home is physically unreachable (`rm -rf ~` inside hits
nothing), and each session gets its own CPU/RAM caps. Your `~/.claude` is shared
in, so sessions, memory, MCP, and auth carry over from the host.

It's an **accident + resource boundary - not protection against a malicious
agent** (it has full network, and your credentials are reachable). Where your org
ships a managed Claude policy, that governs permissions. Details under [Docs](#docs).

## Prerequisites

- `podman` (rootless) - `sudo apt-get install podman`.
- cgroup v2 with user delegation (for the resource caps). If Podman warns the
  limits are ignored: `sudo systemctl edit user@.service`, add
  `[Service]` then `Delegate=cpu cpuset io memory pids`, and re-login.

## Setup

```
git clone <this-repo> ~/tools/claude-setup     # keep it OUT of ~/github (the mounted tree)
ln -s ~/tools/claude-setup/bin/claude-sandbox ~/.local/bin/claude-sandbox
claude-sandbox build                           # one-time; rebuild after editing the Containerfile
```

`build` bakes in your host UID/GID/username (so `--userns=keep-id` maps you 1:1
and files stay yours) and your `git config --global` identity.

## Usage

```
cd ~/github/some-project       # any dir under ~/github
claude-sandbox                 # launch - all of ~/github mounted, session starts here
claude-sandbox --resume        # extra args pass through to `claude`
claude-sandbox doctor          # diagnostics: mounts, keep-id, toolchain, caps
claude-sandbox build           # (re)build the image
```

Auth, sessions, and MCP come from your shared `~/.claude` - no separate login. For
parallel work, run `claude-sandbox` in another terminal (one container each; pairs
with `git worktree`).

## What's in the image

Go, Node + corepack (pnpm/yarn), Python, make/build-essential, gh, kubectl, helm,
gcloud, az, podman (+ a `docker` shim), Claude Code. amd64 - for arm64, swap the
Go/kubectl download arch in `Containerfile`.

## Knobs (env vars)

| Var | Default | Effect |
|-----|---------|--------|
| `CLAUDE_SANDBOX_AUTO` | `1` | `0` drops `--dangerously-skip-permissions` (a no-op if your org disables bypass - see docs) |
| `CLAUDE_SANDBOX_MEMORY` | `8g` | Per-session memory cap |
| `CLAUDE_SANDBOX_CPUS` | `4` | Per-session CPU cap |
| `CLAUDE_SANDBOX_PIDS` | `1024` | Per-session process cap |
| `CLAUDE_SANDBOX_ROOT` | `~/github` | Mounted tree + allowed launch root |
| `CLAUDE_SANDBOX_IMAGE` | `claude-sandbox:latest` | Image tag |

## Docs

- [Permissions & managed org policy](docs/permissions.md) - auto mode, why bypass may be a no-op, the allow-list approach.
- [Your `~/.claude` (shared)](docs/claude-home.md) - what's shared vs read-only, the `settings.json` override, the risk scope.
- [Clusters: kubeconfig, kind, docker](docs/clusters.md) - host-provisioned cluster + the in-sandbox test loop.
- [Scoping `gh` with a fine-grained PAT](docs/github-pat.md) - HTTPS vs SSH, permission mapping, what tokens can't enforce.
- [Autonomous clusters via a host helper](docs/option-1-host-make-helper.md) - deferred design.

## Notes

- Keep this repo **outside** `~/github`: it defines the boundary and the wrapper
  runs on the host, so it mustn't be writable from inside a session.
- **Host networking** - full network access; host kind clusters and dev servers
  are reachable. Only the network namespace is shared.
- The container sets `CLAUDE_SANDBOX=1` so you, Claude, or a Makefile can detect it.
- Build caches persist in named volumes (`claude-go`, `claude-cache`,
  `claude-pnpm`, `claude-npm`); list with `podman volume ls`, reset with
  `podman volume rm claude-<name>`.
