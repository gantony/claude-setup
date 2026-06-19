# Option 1 - autonomous clusters / e2e via a host helper (deferred)

Status: **deferred.** We're running with option 2 (host-provisioned cluster +
mounted kubeconfig; see the README "Cluster testing" section). Revisit this if
option 2 proves painful - e.g. you frequently need Claude to spin clusters or
deploy its *own* image builds without you in the loop.

## Goal

Let Claude, inside the sandbox, drive the full e2e loop autonomously - including
cluster lifecycle and deploying images it just built - with `make` targets as the
interface, so the same targets run identically in a manual session and on CI.

## Why not just run `make` on the host

A host helper that runs arbitrary `make` targets from the repo is **arbitrary
host code execution**: Claude controls the Makefile (it's in the mounted
`~/github`), so editing any recipe turns `make that-target` into "run anything on
the host". The usual mitigations don't save it:

- Allowlisting *target names* - useless, the agent owns the recipe behind the name.
- Pinning the Makefile to a trusted commit - useless, real targets call repo
  scripts (`./hack/*.sh`, test code) the agent also edits.

Running repo code on the host safely would require a context that can't reach
your home - which is just the sandbox again. So "run make on the host" collapses
to "run make in the sandbox + give the sandbox what those targets need".

## The design

1. **Run make targets in the sandbox.** That container is the CI-parity clean
   environment (CI runs them in a container too). `build`/`test`/`lint`/`fmt`/
   `generate` already work there. No host involvement.
2. **Cross the host boundary only via fixed verbs.** A small host daemon listens
   on a unix socket (mounted into the sandbox) and accepts a *fixed* set of verbs
   - `up` / `down` / `reset` (maybe `load`) - each mapped to a hardcoded host
   script. **Zero agent-supplied input**: no command string, no target name, no
   repo path that reaches a shell. There's nothing for the agent to poison.
   The instant a verb takes a free-form argument that hits a shell, it's RCE again.
3. **Pin the kind config host-side.** The helper creates the cluster from a config
   it owns (in this repo, outside `~/github`), never from the mutable repo - kind
   config supports `extraMounts`, so an agent-supplied config is itself a host
   escape. (matrix's `e2e/kind-config.yaml` is benign today - just a node label -
   so pinning a copy is trivial.)

## e2e refactor required (matrix `e2e/Makefile`)

The Makefile is already cleanly split, which helps:

| Target | Runs in sandbox? | Change needed |
|---|---|---|
| `test` (deploy+test+teardown, in Go via kubeconfig) | yes, ~as-is | none |
| `cluster-create` / `cluster-delete` (`kind create/delete`) | no (host op) | route to the helper |
| `build-images` -> `kind-load-*` (build + `kind load`) | no (`kind load` half) | change image delivery |

- **Cluster create/delete:** put the command behind a variable
  (`CLUSTER_CREATE_CMD ?= kind create cluster ...`, overridden to the socket
  client in the sandbox) or ship a `kind` shim in the image that forwards
  `create/delete cluster` to the helper and passes everything else through. CI
  keeps using `kind` directly. Helper uses the pinned `kind-config.yaml`.
- **Image delivery** (the real work, lives in the *root* Makefile's `kind-load-*`,
  not `e2e/Makefile`): the sandbox can't `kind load`. Two routes:
  - **(i) local registry** - `ko` pushes to `localhost:5000`, the cluster pulls.
    Cleanest, but deploy image refs become `localhost:5000/...` (repo-wide-ish),
    and for CI parity you'd adopt the registry on CI too.
  - **(ii) tarball + helper `load`** - sandbox `ko` writes an image archive to a
    shared dir, a helper verb runs `kind load image-archive` host-side. Keeps
    image refs as plain `latest` tags (smaller repo blast radius), but adds a verb
    that takes a (validated) path.
- **CI parity:** standardize image delivery across CI / host / sandbox so the
  same `make` targets behave identically everywhere. Only *cluster provisioning*
  differs (real `kind` on CI/host vs the socket helper in the sandbox), behind
  one variable.

## Risk posture

Safe as long as the host boundary is crossed only through fixed verbs with no
agent-authored commands or recipes, and the kind config is host-pinned. This is
strictly tighter than mounting the raw podman socket (which lets the agent craft
arbitrary containers, including ones that bind-mount your home).
