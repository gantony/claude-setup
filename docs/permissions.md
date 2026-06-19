# Permissions, auto mode, and managed org policy

By default the wrapper passes `--dangerously-skip-permissions` (set
`CLAUDE_SANDBOX_AUTO=0` to drop it). **But if your org delivers managed Claude
settings that set `disableBypassPermissionsMode`, that flag is a no-op** - you're
always in the org's prompting mode regardless, and bypass simply isn't available
(by design - don't try to strip it; take exceptions up with whoever owns the org
policy).

In that case the org policy governs:

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
