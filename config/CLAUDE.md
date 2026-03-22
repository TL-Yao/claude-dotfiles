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

## MCP Tool Preferences

When the task involves these capabilities, MUST use the corresponding MCP tool instead of alternative approaches:

- **Excel files** (.xlsx/.xls): Use `excel` MCP tools (NOT Python/pandas via Bash)
- **Diagrams/flowcharts**: Use `mcp-mermaid` to render diagrams as images (NOT just output Mermaid code text)
- **PDF generation**: Use `markdown2pdf` MCP to convert content to PDF (NOT just output Markdown)
- **Remote server SSH**: Use `ssh-mcp-server` MCP tools (classfang/ssh-mcp-server, globally installed). If target machine hasn't been configured in ssh-mcp-server yet, use traditional `ssh` one-shot via Bash to set it up first, then switch to MCP tools.
- **Browser automation**: Use `agent-browser` skill (Bash CLI, default choice for most tasks). Use `chrome-devtools` MCP when needing real authenticated Chrome session, performance auditing, or network debugging. Use `claude-in-chrome` MCP only for screenshots/GIFs/visual verification.

These MCP tools produce actual files. Always prefer them over text-only alternatives.

## Code Quality Skills

When writing or reviewing code in these languages, invoke the corresponding skill:

- **Go**: `/use-modern-go` (JetBrains, auto-detects go.mod version)
- **React/JSX**: `react-expert` skill (React 19, Server Components, TanStack Query v5)
- **Rust**: `rust-engineer` skill (ownership, async, unsafe, error handling)
- **TypeScript/JS**: `typescript-pro` skill (advanced types, patterns, config)
- **Python**: `python-pro` skill (async, type system, testing patterns)
- **Code Review**: `code-review-skill` (multi-language review guidelines + CSS)

LSP plugins (typescript-lsp, rust-analyzer-lsp, gopls-lsp, pyright-lsp) provide
real-time diagnostics automatically — no manual invocation needed.

## Secret Protection (MANDATORY)

**NEVER commit secrets** (API tokens, passwords, private keys) to any Git repository. This is a hard rule with zero exceptions.

Before every `git add` or `git commit`:
- Scan staged files for patterns: `*_TOKEN`, `*_KEY`, `*_SECRET`, `apify_api_*`, `sk-*`, `ghp_*`, `gho_*`, bearer tokens, passwords
- If a file contains secrets, replace with placeholders (`YOUR_*_HERE`) or use environment variables before committing
- **Config export scripts** (like dotfiles export.sh) MUST have built-in secret sanitization — never rely on manual review

If you discover a secret already committed:
1. **Immediately alert the user** — this is a security incident
2. Use `git filter-repo --replace-text` to purge from all history
3. Force push the cleaned history
4. Remind user to **rotate/revoke the leaked credential**

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

### 1. Record Learnings (two-tier routing)

**Project-specific** (-> project CLAUDE.md under `## Takeaways`):
- Project-unique gotchas, architecture decisions, environment config
- Criteria: wouldn't apply in a different project
- Format: `### [YYYY-MM-DD] - [Category]` with Problem/Solution/Prevention (3 lines max)

**Cross-project** (-> `~/.claude/learnings/LEARNINGS.md`):
- Tool usage tips, language idioms, general debugging experience
- Criteria: would encounter this in other projects too
- Follow the Write-time Protocol (Rule 6) when adding entries

**Do NOT record**: trivial fixes, obvious things, or information already in the codebase.
**Maintenance**: When adding a new entry, scan existing ones — merge duplicates, remove outdated entries.

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
- `~/.claude/learnings/LEARNINGS.md` (global learnings)
- `~/.claude/hooks/*` (hook scripts)
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

### 6. Global Learning Write-time Protocol

**When**: About to write a new entry to `~/.claude/learnings/LEARNINGS.md`.

**Steps**:
1. Read the file, grep for similar existing entries (by Summary keywords)
2. If similar entry exists: update Occurrences +1, append current project to Projects list
3. If Occurrences reaches 3: distill into 1-2 line rule, append to `~/.claude/CLAUDE.md` under `## Promoted Rules`, mark original as `promoted`
4. If no similar entry: create new with `Occurrences: 1`, `Projects: <current>`
5. If `last-cleanup` date > 30 days ago: also run cleanup (delete `archived` entries >30d old, merge duplicates, update date)
6. Trigger dotfiles sync (Rule 5)

**Entry format**:
```
## [YYYY-MM-DD] category | status

**Summary**: one-line description
**Details**: what happened, what's correct
**Action**: specific fix or rule
**Occurrences**: N
**Projects**: project-a, project-b
```

**Status values**: `active` | `promoted` | `archived`
