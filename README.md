# claude-setup

Run Claude Code inside a rootless [Podman](https://podman.io/) container so the
**container is the structural boundary**: all of `~/github` (so a session can span
multiple repos) plus this repo's `kube/` dir are mounted, so the rest of your home
partition is physically unreachable - `rm -rf ~` inside the sandbox hits nothing.
Per-session CPU/RAM caps come from the same mechanism.

Because the boundary is structural, Claude runs in auto mode
(`--dangerously-skip-permissions`) by default.

## Layout

| Path | What |
|------|------|
| `Containerfile` | Dev image: Go, Node + corepack (pnpm/yarn), Python, make/build-essential, gh, kubectl, helm, gcloud, az, podman (+ `docker` shim), Claude Code |
| `bin/claude-sandbox` | Launch wrapper - build the image, then run Claude in any `~/github` dir |
| `settings/settings.json` | Curated container settings, mounted read-only over `~/.claude/settings.json` |
| `kube/` | Gitignored kubeconfigs for Claude; mounted as the container's `~/.kube` (see `kube/README.md`) |

## Prerequisites

- `podman` (rootless). On Ubuntu: `sudo apt-get install podman`.
- cgroup v2 with user delegation, so `--memory`/`--cpus`/`--pids-limit` are
  honored for rootless containers (default on modern systemd distros). If
  Podman warns that limits are ignored, enable delegation:
  `sudo systemctl edit user@.service` ->
  `[Service]` / `Delegate=cpu cpuset io memory pids`, then re-login.

## Setup

```
git clone <this-repo> ~/tools/claude-setup        # keep it OUT of ~/github (the mounted tree)
ln -s ~/tools/claude-setup/bin/claude-sandbox ~/.local/bin/claude-sandbox
claude-sandbox build                              # one-time (rebuild after editing the Containerfile)
```

`build` bakes in your host UID/GID/username so `--userns=keep-id` maps you 1:1 -
files Claude creates in mounted repos stay owned by you on the host.

## Usage

```
cd ~/github/some-project        # any dir under ~/github
claude-sandbox                  # auto mode; starts here, all of ~/github mounted
claude-sandbox --resume         # extra args pass through to `claude`
```

Auth is shared with your host `~/.claude`, so you're already logged in - no
separate `/login` needed.

## Doctor

`claude-sandbox doctor` runs the same container setup (mounts, caps, userns) but
executes a diagnostic instead of Claude, then exits. It reports:

- identity / keep-id (new files in the repo owned by you, not a stray uid)
- the `~/.claude` mounts: `settings.json` read-only with no bash-sandbox block,
  `CLAUDE.md`/`commands`/`hooks`/`.git` read-only, `projects/` writable
- the toolchain (go, node, pnpm, ..., podman, docker shim, claude)
- nested podman (the docker/kind path)
- the resolved cgroup memory/cpu/pids caps

Run it from any dir under `~/github` after a build or a config change.

## Your `~/.claude` (shared with the host)

Your real `~/.claude` is mounted **read-write**, so the sandbox shares one store
with the host: sessions, `history.jsonl`, `projects/` (transcripts + memory),
auth, custom commands (review-pr, open-pr, ...), hooks and plugins are all the
same. So you can resume a host session inside the sandbox and vice versa, memory
is shared, and you don't log in twice.

The one exception is `settings.json`: the container mounts the curated
`settings/settings.json` **read-only** over it, because your host settings enable
the built-in bash sandbox and the claude-guard hook - both of which break or are
redundant inside the container. Your other settings tiers still apply
(`settings.local.json`, and remote settings - whose panther hooks are guarded
with `[ -x ]` and no-op when the binary isn't present).

Scope of risk: your **host** Claude already has full read-write to `~/.claude`, so
the sandbox isn't a new risk class - it just gets the same access, to share the
store. Its real job (protecting the rest of your home, capping resources) is
unchanged. Your config inputs (`CLAUDE.md`, `commands/`, `hooks/`) and the
`~/.claude` `.git` repo are mounted **read-only**: the container can't clobber your
config or commit/push changes into your dotfiles repo, so the host stays the
control point for versioned config (pull there to apply updates). Sessions, memory
and runtime state stay writable (that's the shared store). Settings/model changes
made inside the sandbox won't persist (settings.json is read-only there) - edit
`settings/settings.json` here.

This is an **accident + resource boundary, not an anti-exfiltration one.** A
container in auto mode with full network and readable credentials could, if it
went truly rogue, copy and push your code or read your tokens - read-only mounts
don't stop that (the `.git` mount stops casual/accidental config tampering, not a
determined copy-out). Defending against a malicious agent is a different posture
(network egress allowlist, no mounted credentials) you've intentionally traded
away for convenience.

## Auto mode vs oversight mode

- **Auto (default):** `--dangerously-skip-permissions` - no prompts. The
  container is the guardrail. `settings/settings.json` is ignored in this mode.
- **Oversight:** `CLAUDE_SANDBOX_AUTO=0 claude-sandbox` - prompts apply and the
  permission tiers in `settings/settings.json` take effect. Use this when you
  hand Claude a sensitive (e.g. staging) kubeconfig and want to watch each call.

## Kubeconfigs

Your host CLI keeps its own `~/.kube/config` (never mounted). Claude gets a
separate `~/.kube` backed by the gitignored `kube/` dir in this repo. Use it for
kind clusters (full access) and the occasional monitored staging config - see
`kube/README.md`.

## Docker / kind

`make` and the daemonless image build (`ko`) work as-is. For anything that calls
`docker` or spins up `kind`, the image ships **podman** plus the `podman-docker`
shim, so `docker build`/`docker run` transparently use podman (no daemon), and
`kind` is pointed at podman via `KIND_EXPERIMENTAL_PROVIDER=podman`.

Caveat: nested rootless containers are finicky. `--userns=keep-id` (which keeps
file ownership clean) gives the container a single UID mapping, which limits what
nested podman can map - simple `docker build`/`run` are fine, but full `kind`
e2e may need tuning or is simplest to run on the host. Test the e2e path before
relying on it. The `--cap-drop ALL` / `no-new-privileges` hardening was removed
because it blocks rootless podman's setuid helpers; the filesystem and resource
boundaries (what's mounted, the CPU/RAM caps) are unaffected.

## Persistent caches

Named volumes keep module downloads across sessions and share them between
parallel containers (no re-downloading per launch):

`claude-go` (`~/go` + build cache), `claude-cache` (`~/.cache`: go-build, pip,
yarn), `claude-pnpm` (pnpm store), `claude-npm` (`~/.npm`). Inspect with
`podman volume ls`; reset one with `podman volume rm claude-<name>`.

## Parallel sessions

Open another terminal and run `claude-sandbox` in a different worktree - each is
its own container with its own resource caps. Pairs naturally with `git worktree`.

## Knobs (env vars)

| Var | Default | Effect |
|-----|---------|--------|
| `CLAUDE_SANDBOX_AUTO` | `1` | `0` drops `--dangerously-skip-permissions` (oversight mode) |
| `CLAUDE_SANDBOX_MEMORY` | `8g` | Per-session memory cap |
| `CLAUDE_SANDBOX_CPUS` | `4` | Per-session CPU cap |
| `CLAUDE_SANDBOX_PIDS` | `1024` | Per-session process cap |
| `CLAUDE_SANDBOX_ROOT` | `~/github` | Mounted tree + allowed launch root |
| `CLAUDE_SANDBOX_IMAGE` | `claude-sandbox:latest` | Image tag |

## Notes

- Keep this repo **outside** `~/github` (the mounted tree). It defines the sandbox
  boundary and the wrapper runs on the host, so it must not be writable from inside
  a sandbox session - otherwise a session could weaken its own next launch.
- Uses host networking: Claude has full network access and kind clusters /
  local dev servers on the host are reachable. Only the network namespace is
  shared - the filesystem and resource boundaries are unaffected.
- Image is amd64. On arm64, swap the Go/kubectl download arch in `Containerfile`.
- Don't enable Claude's built-in bash sandbox on top of this - the container is
  already the boundary, and its filesystem glob rules are only partially
  supported on Linux.
