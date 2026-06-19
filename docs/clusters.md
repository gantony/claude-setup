# Clusters: kubeconfig, kind, docker

## Kubeconfigs

Your host CLI keeps its own `~/.kube/config` (never mounted). Claude gets a
separate `~/.kube` backed by the gitignored `kube/` dir in this repo. Use it for
kind clusters (full access) and the occasional monitored staging config - see
[`../kube/README.md`](../kube/README.md).

## Docker / kind

`make` and the daemonless image build (`ko`) work as-is. For anything that calls
`docker` or spins up `kind`, the image ships **podman** plus the `podman-docker`
shim, so `docker build`/`docker run` transparently use podman (no daemon), and
`kind` is pointed at podman via `KIND_EXPERIMENTAL_PROVIDER=podman`.

Caveat: nested rootless containers are finicky. `--userns=keep-id` (which keeps
file ownership clean) gives the container a single UID mapping, which limits what
nested podman can map - simple `docker build`/`run` are fine, but full `kind` e2e
may need tuning or is simplest to run on the host. Test the e2e path before
relying on it. (`--cap-drop ALL` / `no-new-privileges` hardening was removed
because it blocks rootless podman's setuid helpers; the filesystem and resource
boundaries are unaffected.)

## Cluster testing (host-provisioned, sandbox-tested)

The sandbox can't create kind clusters or `kind load` images - that needs host
container-runtime access we deliberately withhold. So the current approach
provisions the cluster on the **host** and lets the sandbox deploy/test against it
over the mounted kubeconfig + host networking:

1. On the host, bring up the cluster and load images (matrix e2e example):
   `make -C ~/github/tigera/matrix/e2e setup`
2. Export its kubeconfig into this repo's `kube/` so the sandbox picks it up:
   `kind get kubeconfig --name matrix-e2e > ~/tools/claude-setup/kube/config`
3. In the sandbox, run tests against it - `kubectl`/`helm` reach the API on
   `127.0.0.1` via host networking: `make -C e2e test`

Limitation: the sandbox tests whatever images the host loaded. To deploy images
the sandbox *itself* builds (e.g. to test Claude's own code changes end to end),
you need a local-registry or tarball image path and a host helper for cluster
lifecycle - the deferred work in
[option-1-host-make-helper.md](option-1-host-make-helper.md). For now, rebuild +
reload images on the host when the code under test changes.
