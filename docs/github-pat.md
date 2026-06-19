# Scoping gh in the sandbox with a fine-grained PAT

By default the sandbox mounts your full host `~/.config/gh` (act-as-you on every
repo). To narrow that, drop a **fine-grained PAT** in `secrets/gh-token` and the
wrapper passes it as `GH_TOKEN` instead (gh prefers `GH_TOKEN` over stored login).

**Honest framing first:** the agent can read its own `GH_TOKEN` and, with full
network, could exfiltrate it. So the token's **scope + short expiry** are the
real protection - not secrecy from the agent. Scope it to exactly the repos and
permissions Claude needs, and set a short expiry.

## Create the token

GitHub -> Settings -> Developer settings -> Fine-grained tokens -> Generate new
token. Set:
- **Resource owner**: your account / org that owns the repos.
- **Repository access**: only the specific repos Claude works on (not "all").
- **Expiration**: short (the scope is the guardrail, expiry limits the window).
- **Repository permissions**: as below.

## Recommended permissions

| Permission | Level | Why |
|---|---|---|
| Metadata | Read | Mandatory for any fine-grained PAT |
| Contents | Read and write | Commit + push (also enables merge + release create/edit/**delete** - unavoidable) |
| Pull requests | Read and write | Open / update PRs |
| Actions | Read and write | CI: view + re-run + cancel + dispatch (also enables **delete run** - unavoidable). Use **Read** for view-only |
| Workflows | *omit* | Leaving it off blocks pushes that touch `.github/workflows/*` - Claude can drive CI but not rewrite it |
| Administration | *omit* | No repo-settings/branch-protection changes |

## What the token CAN'T enforce (and what does instead)

Fine-grained PATs are coarse around the destructive boundary. These wishlist
items are **not** token-expressible:

- **"Push but not merge"** - merge and push are the same permission
  (Contents: write). Enforce no-merge via **branch protection / rulesets**
  (require a pull request before merging, required reviews/checks). Main branch
  protection already does this for `main`.
- **"Limit force-push"** - not a token permission at all. Use the branch ruleset
  **Block force pushes** on the branches you want protected.
- **"Create releases but not delete them"** - same permission (Contents: write),
  and there's no ruleset for release deletion. No server-side guardrail exists.
- **"Re-run CI but not delete a workflow run"** - same permission
  (Actions: write), no ruleset. View-only (Actions: Read) is the only separable
  point.

So for delete-release / delete-run there's no structural control: either accept
it (and do those destructive ops on the host), drop the relevant write
permission (losing the benign writes too), or front the GitHub API with a
filtering proxy (heavy - the GitHub equivalent of the docker-socket-proxy we
rejected). Source:
https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens

## Use it

```
echo 'github_pat_xxx' > ~/tools/claude-setup/secrets/gh-token
```

Relaunch `claude-sandbox`; `claude-sandbox doctor` and `gh auth status` inside
confirm it's active.
