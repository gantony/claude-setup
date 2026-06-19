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
| Workflows | *omit* | Blocks pushes touching `.github/workflows/*` (rejected on any branch, so it can't sneak in via a PR either). Guards workflow *definitions* only - NOT the code CI runs; see below |
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
- **"Push code but block (or read-only) releases"** - impossible. `git push` and
  all release writes (`POST`/`PATCH`/`DELETE /releases`) are the *same* permission,
  Contents: write (confirmed in the GitHub docs - there is no standalone Releases
  permission and no read-only-releases setting). A token that can push can always
  create/edit/delete releases. A `gh` shim that refuses `gh release` is bypassable
  (`gh api`, curl) - theater. Tag rulesets only leakily block release *creation via
  a new tag*, not edits/deletes. The only real block is a TLS-terminating proxy
  filtering `api.github.com` `/releases` routes (heavy: MITM + CA cert, sees all
  traffic incl the token). Otherwise: accident model - releases are a host activity.
- **"Re-run CI but not delete a workflow run"** - same permission
  (Actions: write), no ruleset. View-only (Actions: Read) is the only separable
  point.
- **"Omitting Workflows protects CI"** - only partly. It blocks pushing changes
  to `.github/workflows/*` (the push is rejected on any branch, so it can't reach
  a PR either - the permission gates the push, not the merge). But it does NOT
  stop changes to the *code* CI runs (`Makefile`, `hack/*.sh`, tests) - those push
  fine under Contents: write and execute in CI on same-repo PRs (which have
  secrets, on PR open - no merge needed) and on base after merge. Defending that
  is PR review + scoping CI secrets behind Environments with required reviewers,
  not the token.

So for delete-release / delete-run there's no structural control: either accept
it (and do those destructive ops on the host), drop the relevant write
permission (losing the benign writes too), or front the GitHub API with a
filtering proxy (heavy - the GitHub equivalent of the docker-socket-proxy we
rejected). Source:
https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens

## Working on workflow files

With Workflows omitted, Claude can still **edit and commit** changes to
`.github/workflows/*` in the sandbox (editing files and `git commit` are local -
no token needed); only the **push** is rejected. Because `~/github` is a shared
mount, that commit is already in your repo on disk, so you just `git push` from a
host terminal to land it. Rare operation, and it routes workflow changes through
the host on purpose.

## Use it

```
echo 'github_pat_xxx' > ~/tools/claude-setup/secrets/gh-token
```

Relaunch `claude-sandbox`; `claude-sandbox doctor` and `gh auth status` inside
confirm it's active.

Works with SSH remotes too: a PAT is HTTPS auth and can't be used over SSH, so the
image rewrites github SSH remotes (`git@github.com:…`) to HTTPS and uses the token
(`git config --system url.insteadOf` + gh as the credential helper). You don't need
an SSH key in the sandbox - and shouldn't add one, since it's a broad credential
the agent could read. Your host's SSH remotes and keys are untouched.
