# Permissions, auto mode, and managed org policy

By default the wrapper launches Claude with `--permission-mode auto`
(`CLAUDE_SANDBOX_PERMISSION_MODE=auto`). Auto mode is the classifier-backed mode:
it keeps prompts low for routine work but, unlike bypass, a safety classifier
still vets each action - so it keeps working under a managed org policy. Set
`CLAUDE_SANDBOX_PERMISSION_MODE=` (empty) for oversight mode (the flag is omitted
and settings / managed policy decide), or to `acceptEdits`, `plan`, `default`,
or `bypassPermissions` for a specific mode.

We default to auto rather than `bypassPermissions` deliberately: **if your org
delivers managed Claude settings that set `disableBypassPermissionsMode`, bypass
is a no-op** - it's unavailable by design (don't try to strip it; take exceptions
up with whoever owns the org policy). Auto mode sidesteps that entirely.

Whatever launch mode you pick, the org policy still governs:

- its `defaultMode` (e.g. `acceptEdits`, so file edits auto-accept),
- its `ask` list (e.g. Tigera prompts for destructive things - `gh release
  delete`, `gh api -X DELETE`, force-push to protected branches, `kubectl delete
  namespace/node`, `drain`, `eksctl delete`),
- its `deny` list (e.g. protecting security tooling from being disabled).

Those are sharper than anything this repo could set. So `settings/settings.json`
here deliberately carries **only an `allow` list** for the dev tool families
(`kubectl`, `gh`, `gcloud`, `az`) - that stops benign commands prompting on top of
the org policy. `ask` beats `allow`, so the org's destructive-action prompts still
fire over our allow.

Outside a managed org, where bypass actually works, you may want to re-add an
`ask`/`deny` tier in `settings/settings.json`.

Note `settings/settings.json` is mounted **read-only over `~/.claude/settings.json`**
in the container (it's the curated version - see [claude-home.md](claude-home.md)),
so edit it in this repo, not inside the sandbox.
