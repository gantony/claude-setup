# secrets/

On-disk secrets for the sandbox. The whole directory is gitignored except this
README - nothing here is ever committed. It lives outside `~/github`, so the
sandbox can't read these files; the wrapper (host side) reads them and injects
values as env vars.

## `gh-token` - scoped GitHub PAT

Put a fine-grained PAT here (single line, no trailing junk):

```
echo 'github_pat_xxx' > ~/tools/claude-setup/secrets/gh-token
```

The wrapper then passes it as `GH_TOKEN`, which `gh` uses over any stored login.
If this file is absent, the wrapper falls back to mounting your full host
`~/.config/gh` read-only.

See [`../docs/github-pat.md`](../docs/github-pat.md) for which permissions to
grant and what the token model can and can't enforce.

Note: the agent can read its own `GH_TOKEN` and (full network) could exfiltrate
it - so the token's **scope** and a **short expiry** are the protection, not
secrecy. Scope it to the repos and permissions Claude needs, nothing more.
