# Claude Code Dotfiles

Portable Claude Code configuration — one-command setup on any machine.

## What's Included

- **Global CLAUDE.md** — development guidelines, work modes, self-evolution protocol
- **Agents** — 6 custom agent definitions (backend-dev, frontend-dev, code-reviewer, designer-architect, qa-engineer, fullstack-explorer)
- **Skills** — team-up skill for spawning agent teams
- **MCP Servers** — reader-mcp (production-grade web scraping with Cloudflare bypass)
- **Settings** — plugin toggles, permissions
- **MCP Config** — Context7 + reader server configuration

## Quick Start

### Fresh Machine Setup

```bash
git clone git@github.com:YOUR_USER/claude-dotfiles.git ~/claudeProjects/claude-dotfiles
cd ~/claudeProjects/claude-dotfiles
./install.sh
```

The install script will:
1. Create `~/.claude/` directory structure
2. **Merge** config into existing files (won't overwrite your settings)
3. Copy agents and skills (skip existing ones)
4. Build reader-mcp from source
5. Merge MCP server config into `~/.claude.json`
6. Print plugin install commands

### After Install

```bash
# Authenticate
claude login

# Install plugins (printed by install.sh)
claude plugin install superpowers@claude-plugins-official
# ... etc
```

## Scripts

### `export.sh` — Export config from current machine

```bash
./export.sh
# Then review and commit:
git diff
git add -A && git commit -m "chore: update config"
git push
```

### `install.sh` — Install on target machine

```bash
# Default: incremental merge (safe, preserves existing config)
./install.sh

# Force: overwrite everything
./install.sh --force
```

**Merge behavior:**

| File | Existing | Missing |
|------|----------|---------|
| `CLAUDE.md` | Append new `##` sections | Copy |
| `settings.json` | Merge plugins (keep existing states) | Copy |
| `agents/*.md` | Skip same-name files | Copy |
| `skills/` | Skip if exists | Copy |
| `reader-mcp/` | Update source, skip build if dist/ exists | Copy + build |
| `.claude.json` | Add/update MCP servers, keep other fields | Create |

### `sync.sh` — Pull + install on other machines

```bash
./sync.sh           # git pull + install.sh (merge mode)
./sync.sh --force   # git pull + install.sh --force
```

## Prerequisites

- **Node.js >= 18** (for reader-mcp build)
- **npm** (for dependencies)
- **python3** (for JSON merging — pre-installed on macOS/modern Linux)
- **rsync** (for file sync — pre-installed on macOS/Linux)
- **Chrome** (optional, for reader-mcp's full browser engine)

## Repository Structure

```
config/
  CLAUDE.md                  # Global instructions
  settings.json              # Plugin toggles + permissions
  claude.json.template       # MCP server config (uses $HOME placeholder)
  plugins.txt                # Declarative plugin manifest
agents/                      # Custom agent definitions
skills/team-up/              # Team-up skill
mcp-servers/reader-mcp/      # Web scraping MCP server source
export.sh                    # Export from current machine
install.sh                   # Install on target machine
sync.sh                      # Pull + install shortcut
```
