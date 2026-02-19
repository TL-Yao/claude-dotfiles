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
mkdir -p "$CLAUDE_DIR"/{agents,skills/team-up,mcp-servers/reader-mcp}

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

# 5. Skills — only add if missing
if [ "$FORCE" = true ] || [ ! -f "$CLAUDE_DIR/skills/team-up/SKILL.md" ]; then
  cp "$REPO_DIR/skills/team-up/SKILL.md" "$CLAUDE_DIR/skills/team-up/"
  echo "  skills/team-up: installed"
else
  echo "  skills/team-up: already exists, skipped"
fi

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

# 8. Summary
echo ""
echo "=== Installation complete ($([ "$FORCE" = true ] && echo "force" || echo "merge") mode) ==="
echo ""
echo "Next steps:"
if ! command -v claude >/dev/null 2>&1; then
  echo "  0. Install Claude Code: npm install -g @anthropic-ai/claude-code"
fi
echo "  1. Run 'claude login' to authenticate (if not already logged in)"
echo "  2. Install marketplace plugins (only those not yet installed):"
while IFS=' ' read -r status plugin || [ -n "$status" ]; do
  [ "$status" = "enabled" ] && echo "     claude plugin install $plugin" || true
done < "$REPO_DIR/config/plugins.txt"
echo ""
echo "  3. (Optional) Disabled plugins you may want later:"
while IFS=' ' read -r status plugin || [ -n "$status" ]; do
  [ "$status" = "disabled" ] && echo "     $plugin" || true
done < "$REPO_DIR/config/plugins.txt"
