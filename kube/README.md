# kube/

Kubeconfigs for Claude to use **inside the sandbox**. This whole directory is
gitignored (except this README) - the files never get committed.

`bin/claude-sandbox` mounts this dir as the container's `~/.kube`, so:

- Claude's kubectl uses these configs; your **host** CLI keeps using your own
  `~/.kube/config` (never mounted into the container). The two are fully separate.
- You can use Claude's config from the host any time:
  `KUBECONFIG=~/tools/claude-setup/kube/config kubectl get pods`

## kind clusters (full access)

kind's API server is on the host loopback, and the sandbox uses host networking
by default, so it's reachable. Export a kind cluster's config here:

```
kind export kubeconfig --name <cluster> --kubeconfig ~/tools/claude-setup/kube/config
```

Claude then has full access to that kind cluster. For the matrix e2e cluster
that's `--name matrix-e2e` (see the README "Cluster testing" section for the full
host-provision -> sandbox-test workflow).

## Staging (monitored, temporary)

Drop a scoped staging kubeconfig here when you want Claude to touch staging,
and run in **oversight mode** so every kubectl call prompts you:

```
CLAUDE_SANDBOX_AUTO=0 claude-sandbox
```

Point at it explicitly if you keep multiple files:
`KUBECONFIG=/path/in/kube kubectl ...`, or merge it into `config`. Delete the
file when you're done to revoke access.
