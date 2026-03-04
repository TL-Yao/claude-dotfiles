#!/bin/bash
# Incrementally install Claude Code config on target machine
# Existing config is preserved — only new content is added
# Use --force to overwrite everything
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

FORCE=false
[ "${1:-}" = "--force" ] && FORCE=true

# Prerequisites
for cmd in node npm python3; do
  command -v "$cmd" >/dev/null || { echo "Error: $cmd not found"; exit 1; }
done
NODE_VER=$(node -v | sed 's/v//' | cut -d. -f1)
[ "$NODE_VER" -ge 18 ] || { echo "Error: Node.js >= 18 required (got $NODE_VER)"; exit 1; }

echo "Installing Claude Code config ($([ "$FORCE" = true ] && echo "FORCE overwrite" || echo "merge mode"))..."
echo ""

# 1. Create directory structure
mkdir -p "$CLAUDE_DIR"/{agents,skills,plugins,mcp-servers/reader-mcp}

# 2. CLAUDE.md — section-aware merge
if [ "$FORCE" = true ] || [ ! -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  cp "$REPO_DIR/config/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
  echo "  CLAUDE.md: installed ($([ "$FORCE" = true ] && echo "overwritten" || echo "new"))"
else
  python3 << 'PYEOF' - "$CLAUDE_DIR" "$REPO_DIR"
import sys

claude_dir = sys.argv[1]
repo_dir = sys.argv[2]

def extract_sections(text):
    sections = {}
    current = None
    lines = []
    for line in text.split('\n'):
        if line.startswith('## '):
            if current:
                sections[current] = '\n'.join(lines)
            current = line
            lines = [line]
        else:
            lines.append(line)
    if current:
        sections[current] = '\n'.join(lines)
    return sections

with open(f"{claude_dir}/CLAUDE.md") as f:
    existing = f.read()
with open(f"{repo_dir}/config/CLAUDE.md") as f:
    incoming = f.read()

existing_sections = extract_sections(existing)
incoming_sections = extract_sections(incoming)

new_sections = []
for heading, content in incoming_sections.items():
    if heading not in existing_sections:
        new_sections.append(content)

if new_sections:
    with open(f"{claude_dir}/CLAUDE.md", 'a') as f:
        f.write('\n\n' + '\n\n'.join(new_sections))
    print(f"  CLAUDE.md: merged {len(new_sections)} new section(s)")
else:
    print("  CLAUDE.md: already up to date")
PYEOF
fi

# 3. settings.json — merge enabledPlugins, add new top-level fields
if [ "$FORCE" = true ] || [ ! -f "$CLAUDE_DIR/settings.json" ]; then
  cp "$REPO_DIR/config/settings.json" "$CLAUDE_DIR/settings.json"
  echo "  settings.json: installed ($([ "$FORCE" = true ] && echo "overwritten" || echo "new"))"
else
  python3 -c "
import json
with open('$CLAUDE_DIR/settings.json') as f:
    existing = json.load(f)
with open('$REPO_DIR/config/settings.json') as f:
    incoming = json.load(f)
for plugin, enabled in incoming.get('enabledPlugins', {}).items():
    if plugin not in existing.get('enabledPlugins', {}):
        existing.setdefault('enabledPlugins', {})[plugin] = enabled
for key, val in incoming.items():
    if key != 'enabledPlugins' and key not in existing:
        existing[key] = val
with open('$CLAUDE_DIR/settings.json', 'w') as f:
    json.dump(existing, f, indent=2)
    f.write('\n')
print('  settings.json: merged')
"
fi

# 4. Agents — only add missing files
ADDED=0
SKIPPED=0
for agent in "$REPO_DIR/agents/"*.md; do
  name=$(basename "$agent")
  if [ "$FORCE" = true ] || [ ! -f "$CLAUDE_DIR/agents/$name" ]; then
    cp "$agent" "$CLAUDE_DIR/agents/"
    ADDED=$((ADDED + 1))
  else
    SKIPPED=$((SKIPPED + 1))
  fi
done
echo "  agents: added $ADDED new, skipped $SKIPPED existing"

# 5. Skills — install all skills, only add missing ones
SKILLS_ADDED=0
SKILLS_SKIPPED=0
for skill_src in "$REPO_DIR/skills/"*/; do
  skill_name=$(basename "$skill_src")
  if [ "$FORCE" = true ] || [ ! -d "$CLAUDE_DIR/skills/$skill_name" ]; then
    mkdir -p "$CLAUDE_DIR/skills/$skill_name"
    rsync -a "$skill_src" "$CLAUDE_DIR/skills/$skill_name/"
    SKILLS_ADDED=$((SKILLS_ADDED + 1))
  else
    SKILLS_SKIPPED=$((SKILLS_SKIPPED + 1))
  fi
done
echo "  skills: added $SKILLS_ADDED new, skipped $SKILLS_SKIPPED existing"

# 6. reader-mcp — copy source + build if needed
rsync -a --exclude node_modules --exclude dist \
  "$REPO_DIR/mcp-servers/reader-mcp/" "$CLAUDE_DIR/mcp-servers/reader-mcp/"
if [ "$FORCE" = true ] || [ ! -f "$CLAUDE_DIR/mcp-servers/reader-mcp/dist/index.js" ]; then
  echo "  reader-mcp: building..."
  (cd "$CLAUDE_DIR/mcp-servers/reader-mcp" && npm install && npm run build)
  echo "  reader-mcp: build complete"
else
  echo "  reader-mcp: source updated, dist/ exists (skip build)"
fi

# 7. ~/.claude.json — merge mcpServers
TEMPLATE=$(sed "s|\\\$HOME|$HOME|g" "$REPO_DIR/config/claude.json.template")
if [ "$FORCE" = true ] || [ ! -f "$HOME/.claude.json" ]; then
  if [ -f "$HOME/.claude.json" ] && [ "$FORCE" = true ]; then
    # Force mode: merge into existing (don't destroy auto-generated fields)
    python3 -c "
import json, sys
with open('$HOME/.claude.json') as f:
    existing = json.load(f)
incoming = json.loads('''$TEMPLATE''')
for key in incoming.get('mcpServers', {}):
    existing.setdefault('mcpServers', {})[key] = incoming['mcpServers'][key]
for key, val in incoming.items():
    if key != 'mcpServers':
        existing[key] = val
with open('$HOME/.claude.json', 'w') as f:
    json.dump(existing, f, indent=2)
    f.write('\n')
print('  .claude.json: force-merged mcpServers + settings')
"
  else
    echo "$TEMPLATE" > "$HOME/.claude.json"
    echo "  .claude.json: installed (new)"
  fi
else
  python3 -c "
import json, sys
with open('$HOME/.claude.json') as f:
    existing = json.load(f)
incoming = json.loads('''$TEMPLATE''')
for key in incoming.get('mcpServers', {}):
    existing.setdefault('mcpServers', {})[key] = incoming['mcpServers'][key]
for key, val in incoming.items():
    if key != 'mcpServers' and key not in existing:
        existing[key] = val
with open('$HOME/.claude.json', 'w') as f:
    json.dump(existing, f, indent=2)
    f.write('\n')
print('  .claude.json: merged mcpServers')
"
fi

# 8. known_marketplaces.json — merge marketplace registrations
if [ -f "$REPO_DIR/config/known_marketplaces.json" ]; then
  if [ "$FORCE" = true ] || [ ! -f "$CLAUDE_DIR/plugins/known_marketplaces.json" ]; then
    cp "$REPO_DIR/config/known_marketplaces.json" "$CLAUDE_DIR/plugins/known_marketplaces.json"
    echo "  known_marketplaces.json: installed ($([ "$FORCE" = true ] && echo "overwritten" || echo "new"))"
  else
    python3 -c "
import json
with open('$CLAUDE_DIR/plugins/known_marketplaces.json') as f:
    existing = json.load(f)
with open('$REPO_DIR/config/known_marketplaces.json') as f:
    incoming = json.load(f)
added = 0
for key, val in incoming.items():
    if key not in existing:
        existing[key] = val
        added += 1
if added:
    with open('$CLAUDE_DIR/plugins/known_marketplaces.json', 'w') as f:
        json.dump(existing, f, indent=2)
        f.write('\n')
    print(f'  known_marketplaces.json: merged {added} new marketplace(s)')
else:
    print('  known_marketplaces.json: already up to date')
"
  fi
fi

# 9. Binary dependencies for LSP plugins
echo ""
echo "Checking binary dependencies..."

# TypeScript LSP needs vtsls
if ! command -v vtsls >/dev/null 2>&1; then
  echo "  Installing @vtsls/language-server + typescript..."
  # Try user-local prefix to avoid sudo
  NPM_PREFIX="${HOME}/.npm-global"
  mkdir -p "$NPM_PREFIX"
  npm config set prefix "$NPM_PREFIX" 2>/dev/null || true
  npm install -g @vtsls/language-server typescript 2>/dev/null && \
    echo "  vtsls: installed to $NPM_PREFIX/bin/" || \
    echo "  vtsls: FAILED — run 'npm install -g @vtsls/language-server typescript' manually"
  # Ensure PATH includes npm-global
  if ! echo "$PATH" | grep -q "$NPM_PREFIX/bin"; then
    SHELL_RC="$HOME/.zshrc"
    [ -f "$HOME/.bashrc" ] && [ ! -f "$HOME/.zshrc" ] && SHELL_RC="$HOME/.bashrc"
    if ! grep -q 'npm-global/bin' "$SHELL_RC" 2>/dev/null; then
      echo "export PATH=\"\$HOME/.npm-global/bin:\$PATH\"" >> "$SHELL_RC"
      echo "  PATH: added ~/.npm-global/bin to $SHELL_RC"
    fi
  fi
else
  echo "  vtsls: already installed ($(which vtsls))"
fi

# Rust analyzer needs rustup + rust-analyzer component
if ! command -v rust-analyzer >/dev/null 2>&1; then
  if command -v rustup >/dev/null 2>&1; then
    echo "  Installing rust-analyzer via rustup..."
    rustup component add rust-analyzer 2>/dev/null && \
      echo "  rust-analyzer: installed" || \
      echo "  rust-analyzer: FAILED — run 'rustup component add rust-analyzer' manually"
  else
    echo "  rust-analyzer: SKIPPED — rustup not installed"
    echo "    Install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    echo "    Then: rustup component add rust-analyzer"
  fi
  # Ensure PATH includes cargo bin
  if [ -d "$HOME/.cargo/bin" ] && ! echo "$PATH" | grep -q "$HOME/.cargo/bin"; then
    SHELL_RC="$HOME/.zshrc"
    [ -f "$HOME/.bashrc" ] && [ ! -f "$HOME/.zshrc" ] && SHELL_RC="$HOME/.bashrc"
    if ! grep -q 'cargo/bin' "$SHELL_RC" 2>/dev/null; then
      echo "export PATH=\"\$HOME/.cargo/bin:\$PATH\"" >> "$SHELL_RC"
      echo "  PATH: added ~/.cargo/bin to $SHELL_RC"
    fi
  fi
else
  echo "  rust-analyzer: already installed ($(which rust-analyzer))"
fi

# Excel MCP needs uv/uvx
if ! command -v uvx >/dev/null 2>&1; then
  echo "  Installing uv (for Excel MCP server)..."
  curl -LsSf https://astral.sh/uv/install.sh 2>/dev/null | sh 2>/dev/null && \
    echo "  uv/uvx: installed" || \
    echo "  uv/uvx: FAILED — run 'curl -LsSf https://astral.sh/uv/install.sh | sh' manually"
else
  echo "  uv/uvx: already installed ($(which uvx))"
fi

# 10. Summary
echo ""
echo "=== Installation complete ($([ "$FORCE" = true ] && echo "force" || echo "merge") mode) ==="
echo ""
echo "Next steps:"
if ! command -v claude >/dev/null 2>&1; then
  echo "  0. Install Claude Code: npm install -g @anthropic-ai/claude-code"
fi
echo "  1. Run 'claude login' to authenticate (if not already logged in)"
echo "  2. Start a Claude Code session, then install plugins:"
echo "     Marketplace plugins need /plugin install in a Claude Code session."
echo "     Run these commands inside claude:"
echo ""
# Check for third-party marketplaces that need to be added first
if [ -f "$REPO_DIR/config/known_marketplaces.json" ]; then
  python3 -c "
import json
with open('$REPO_DIR/config/known_marketplaces.json') as f:
    data = json.load(f)
# Only show non-official marketplaces that need manual add
for name, info in data.items():
    if name not in ('claude-plugins-official', 'superpowers-marketplace'):
        repo = info.get('source', {}).get('repo', '')
        if repo:
            print(f'     /plugin marketplace add {repo}')
"
fi
while IFS=' ' read -r status plugin || [ -n "$status" ]; do
  [ "$status" = "enabled" ] && echo "     /plugin install $plugin" || true
done < "$REPO_DIR/config/plugins.txt"
echo ""
echo "  3. (Optional) Disabled plugins you may want later:"
while IFS=' ' read -r status plugin || [ -n "$status" ]; do
  [ "$status" = "disabled" ] && echo "     $plugin" || true
done < "$REPO_DIR/config/plugins.txt"
echo ""
echo "  4. Restart Claude Code to activate all changes"
