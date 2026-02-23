# Global Development Guidelines

## Language

- Reply in the same language the user uses (Chinese input → Chinese reply, English input → English reply)
- Use English for: code comments, variable names, commit messages, thinking process, inter-module communication
- Default to following the user's language when uncertain

## Two Work Modes

### POC Mode (Fast Exploration)

When working on playground, prototyping, or comparing approaches:

- Prioritize speed over code quality
- Skip tests, omit error handling when not essential
- Provide the fastest working solution
- Summarize takeaways and key conclusions after each exploration

**Triggers**: "试一下", "快速搭一个", "POC", "playground", "try", "quick prototype", "compare"

### Full Development Mode (Production)

When working on formal feature development:

- Follow the full workflow: requirements → design → develop → quality check → test → commit
- Proactively use plan mode for design phase
- Include proper error handling and edge case consideration
- Run code review before committing

**Triggers**: "开发", "实现", "feature", "production", "ship", "implement"

When unsure which mode, ask.

## Code Style

- Keep it simple, no over-engineering
- Meaningful function and variable names, minimize comment dependency
- Do not add unrequested features, refactors, or "improvements"
- Do not add comments or type annotations to unchanged code

## UI/UX Development

**MANDATORY**: When building or modifying any UI/UX — web pages, components, layouts, styling, or frontend interfaces — MUST invoke the `/frontend-design` skill before writing any code. This applies to both POC and Full Development modes.

**Triggers**: creating pages, building components, designing layouts, styling, responsive design, UI refactoring, adding visual elements, form design, dashboard building, landing pages.

**No exceptions**: Even "just add a button" or "change the color" should go through the skill when it involves design decisions.

## Tech Stack Reference

- Backend primary: Go, secondary: Python
- Frontend: JS/React (recommend specific framework based on project needs)
- Future possible: C++, Rust

## Commit Convention

Format: `<type>: <short description>`

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`

Example: `feat: add user authentication endpoint`

## Web Fetching Fallback

When `WebFetch` fails (blocked, 403, etc.), use Cloudflare's `markdown.new` as fallback:

```bash
curl -s "https://markdown.new/https://TARGET_URL"
```

Requests come from Cloudflare's infrastructure instead of Anthropic's servers, bypassing many anti-AI-crawler blocks. Does NOT work for JS-heavy SPAs or login-required content.

## Self-Evolution Protocol

**IMPORTANT**: These behaviors should happen naturally during development, not as afterthoughts. Judge whether something is worth recording — only record what would save significant time if encountered again.

### 1. Record Takeaways (→ Project CLAUDE.md)

**When**: After solving a non-trivial bug, debugging session, exploration, or discovering a project-specific pattern.

**What to record** (append under a `## Takeaways` section in the project's CLAUDE.md):
- Error symptoms + root causes + fixes (so the same bug isn't debugged twice)
- Environment/tooling gotchas with concrete workarounds
- Codebase conventions discovered (naming, structure, error handling patterns)
- Failed approaches and WHY they didn't work (anti-patterns)
- Architecture decisions and their rationale

**Format**:
```
### [YYYY-MM-DD] - [Category]
**Problem**: [What went wrong or what was discovered]
**Solution/Insight**: [What fixed it or what was learned]
**Prevention**: [How to avoid in future, if applicable]
```

**Do NOT record**: trivial fixes, obvious things, or information already in the codebase.
**Maintenance**: When adding a new takeaway, scan existing ones — merge duplicates, remove entries that are now obvious or outdated, keep each entry to 3 lines max.

### 2. Update README.md

**When**: After adding, modifying, or removing a feature — AND tests/verification confirm it works.

**What to update**:
- Feature descriptions and usage instructions
- Setup/installation steps if changed
- API documentation if endpoints changed
- Configuration options if added/removed

**Do NOT**: Create README.md if it doesn't exist (unless asked). Do NOT update README before verifying the feature works.

### 3. Sync Project CLAUDE.md with Reality

**When**: After any of these happen during development:
- Project directory structure changes significantly
- New build/run/test commands are discovered or changed
- Service configuration or ports change
- New dependencies or environment requirements are added

**What to update**: The relevant sections of the project's CLAUDE.md so the next session starts with accurate context.

### 4. Accumulate Code Conventions

**When**: After working on a project long enough to notice recurring patterns.

**What to record** (in project CLAUDE.md under `## Code Conventions`):
- Naming conventions used in the codebase (e.g., "handlers use `HandleXxx` prefix")
- Error handling patterns (e.g., "all API errors return `ApiError` struct")
- Directory structure conventions (e.g., "each feature gets its own package under `internal/`")
- Testing conventions (e.g., "table-driven tests, test files use `_test.go` suffix with package name `_test`")

Only record conventions that are **consistently followed** in the existing code, not aspirational rules.

### 5. Sync Dotfiles Repo

**When**: After modifying any of the following on this machine:
- `~/.claude/CLAUDE.md` (global instructions)
- `~/.claude/settings.json` (plugin toggles, permissions)
- `~/.claude/agents/*.md` (agent definitions)
- `~/.claude/skills/*/SKILL.md` (skill definitions)
- `~/.claude/mcp-servers/*/src/**` (custom MCP server source code)
- `~/.claude.json` top-level `mcpServers` config

**What to do**:
1. Run `~/claudeProjects/claude-dotfiles/export.sh` to export changes
2. Review the diff: `cd ~/claudeProjects/claude-dotfiles && git diff`
3. Commit with descriptive message: `git add -A && git commit -m "chore: <what changed>"`
4. Remind the user to `git push` if they want to sync to other machines

**When NOT to sync**:
- Temporary experimental changes the user hasn't confirmed they want to keep
- Changes to auto-generated files (caches, tokens, project metadata)
- If the user says "don't sync this" or "just trying something"

**Judgment criteria**: Sync when a config change is intentional and permanent.
