## PR Preferences
- Do NOT use a `## Summary` heading - instead start the body with a high-level description of the change
- Do NOT include a "Test plan" section in PR descriptions
- Do NOT include the "Generated with Claude Code" footer
- Do NOT prefix PR titles or descriptions with 🤖
- Do NOT use conventional commit prefixes (e.g. `feat:`, `fix:`, `docs:`) in PR titles - use plain English (e.g. "Enable versioned docs" not "docs: enable versioned docs")
- When replying to PR comments on behalf of me, prefix with 🤖 to distinguish from my own replies
- When writing GitHub issues or other public content (not PR titles/descriptions) on behalf of me, prefix with 🤖
- Always create PRs as **draft** by default (use `--draft` flag). Only create non-draft if explicitly asked.
- When replying to PR review comments, always reply **inline** in the review thread (`gh api .../comments/{id}/replies`), not as a general PR comment (`gh pr comment`)
- Always ask before posting comments on PRs or issues
- When asked to "review PR comments", present a summary for discussion first - do NOT reply on the PR unless explicitly asked to
- Do NOT include a "Files changed" section in PR descriptions - the diff is visible in GitHub and the list goes stale with revisions
- **Never force-push** (`git push --force` / `--force-with-lease`) to PR branches. Add new commits instead (including revert commits to undo changes) - they show iteration history and will be squashed on merge. Only force-push if explicitly asked.

## Writing Style
- Use `-` (hyphen) instead of `—` (em dash) everywhere

## Worktree / Settings Awareness
- This user works with git worktrees inside the `matrix` repo, so each worktree gets its own `.claude/projects/` directory
- When saving preferences or learned patterns, choose the right location:
  - **`~/.claude/CLAUDE.md`** (this file) - personal preferences that apply everywhere (PR style, auto-approval settings, workflow preferences)
  - **`~/.claude/settings.json`** - personal auto-approval rules and tool permissions
  - **Repo `CLAUDE.md`** (checked into git) - repo conventions, coding standards, hooks, build commands - anything the team should share
  - **Project memory** (`~/.claude/projects/.../memory/`) - only for transient context specific to one worktree
- Proactively update these files when discovering new patterns, conventions, or preferences during work - don't wait to be asked

## Bash Tool Usage
- Do NOT chain shell commands with `&&` or `;` - use separate tool calls instead (or parallel calls when independent). Chained commands bypass permission patterns and trigger unnecessary approval prompts.
- **Routine commands (commit messages, temp build artifacts):** write to a temp file with the Write tool to avoid `$()` substitution prompts. E.g. write to `/tmp/commit-msg.txt`, then `git commit -F /tmp/commit-msg.txt`.
- **Commands the user should review (PR creation/editing, posting comments, destructive ops):** use inline `$()` substitution so the full content is visible in the approval prompt. The prompt itself is the review mechanism - don't hide the content in a temp file.
- **Structured JSON payloads (GitHub API reviews, etc.):** use `--input -` with a quoted heredoc (`<<'EOF'`) so the full content is visible in one approval prompt without temp files. The quoted heredoc prevents shell expansion, keeping backticks and `$` safe.
- For other cases where approval isn't needed: use the Write tool to create input files, or restructure the command to avoid substitution.

## GitHub Review Comments
- Use `line`/`side` fields (not `position`) when placing inline review comments - `position` is a fragile diff-hunk offset that's easy to get wrong.
- **Before ANY review-related API call** (creating reviews, replying to comment threads), check for and delete pending reviews as a standard first step - not just as error recovery. The GitHub API only allows one pending review per user per PR, and partial failures or interrupted calls silently leave orphans that block all subsequent review operations. Check with `gh api .../reviews --jq '.[] | select(.state == "PENDING") | .id'` then DELETE each.
- Never delegate comment posting to sub-agents - they can't recover from API errors and leave orphaned pending reviews. Sub-agents gather and analyse; the main context posts.

## claude-guard
- This user runs [claude-guard](https://github.com/gantony/claude-guard) as a PermissionRequest hook. It auto-approves commands matching `~/.config/claude-guard/policy.json` and logs all decisions to `~/.local/share/claude-guard/decisions.jsonl`.
- When asked to review claude-guard usage, run `claude-guard review --since <duration>`.
- Policy changes take effect immediately (no restart needed).

## Permissions Management
- **All reusable tool permissions belong in `~/.claude/settings.json` (global), not in project-local `.claude/settings.local.json` files.**
- When a new permission is approved during a session and gets saved to `.claude/settings.local.json`, immediately also add it to `~/.claude/settings.json` so it applies across all worktrees. Then remove the local entry.
- At the start of a session, if `.claude/settings.local.json` exists in the current project, check whether its entries are already in `~/.claude/settings.json`. If not, offer to merge them up and delete the local file.
