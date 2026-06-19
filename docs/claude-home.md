# Your `~/.claude` (shared with the host)

Your real `~/.claude` is mounted **read-write**, so the sandbox shares one store
with the host: sessions, `history.jsonl`, `projects/` (transcripts + memory),
auth, custom commands (review-pr, open-pr, ...), hooks and plugins are all the
same. So you can resume a host session inside the sandbox and vice versa, memory
is shared, and you don't log in twice.

The sibling `~/.claude.json` (projects index, user-scoped MCP servers, trust
state) is mounted too. If Claude ever stops persisting config inside the sandbox,
that single-file mount is the suspect (atomic-rename can't write over a
bind-mounted file); drop it and you just lose MCP/trust sharing, nothing else.

## What's read-only

- **`settings.json`**: the container mounts the curated `settings/settings.json`
  read-only over it, because your host settings enable the built-in bash sandbox
  and the claude-guard hook - both of which break or are redundant inside the
  container. Your other settings tiers still apply (`settings.local.json`, and
  remote settings - whose panther hooks are guarded with `[ -x ]` and no-op when
  the binary isn't present). See [permissions.md](permissions.md).
- **`CLAUDE.md`, `commands/`, `hooks/`, `.git/`**: read-only. The container can't
  clobber your config or commit/push into your dotfiles repo, so the host stays
  the control point for versioned config (pull there to apply updates).

Sessions, memory, and runtime state stay writable - that's the shared store.
Settings/model changes made inside the sandbox won't persist (settings.json is
read-only there); edit `settings/settings.json` in this repo instead.

## Risk scope (honest)

Your **host** Claude already has full read-write to `~/.claude`, so the sandbox
isn't a new risk class - it just gets the same access, to share the store. Its
real job (protecting the rest of your home, capping resources) is unchanged.

This is an **accident + resource boundary, not an anti-exfiltration one.** A
container with full network and readable credentials could, if it went truly
rogue, copy and push your code or read your tokens - read-only mounts don't stop
that (the `.git` mount stops casual/accidental config tampering, not a determined
copy-out). Defending against a malicious agent is a different posture (network
egress allowlist, no mounted credentials) intentionally traded away for
convenience.

## The `claude` binary

Claude Code is npm-installed at `/usr/bin/claude`, with a symlink at
`~/.local/bin/claude` so its startup integrity check (which expects the native
installer location, recorded in the shared `~/.claude.json`) is satisfied and
doesn't warn.
