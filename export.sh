#!/bin/bash
# Export portable Claude Code config from ~/.claude/ into this repo
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Exporting Claude Code config..."

# Tier 1: Direct copy files
cp ~/.claude/CLAUDE.md "$REPO_DIR/config/"
echo "  config/CLAUDE.md"
cp ~/.claude/settings.json "$REPO_DIR/config/"
echo "  config/settings.json"

# Tier 2: Agents + Skills
cp ~/.claude/agents/*.md "$REPO_DIR/agents/"
echo "  agents/*.md"
cp ~/.claude/skills/team-up/SKILL.md "$REPO_DIR/skills/team-up/"
echo "  skills/team-up/SKILL.md"

# Tier 3: reader-mcp source (exclude build artifacts)
rsync -a --delete --exclude node_modules --exclude dist --exclude .DS_Store \
  ~/.claude/mcp-servers/reader-mcp/ "$REPO_DIR/mcp-servers/reader-mcp/"
echo "  mcp-servers/reader-mcp/ (source only)"

# Tier 4: Extract portable fields from ~/.claude.json, replace $HOME with placeholder
python3 -c "
import json, os
with open(os.path.expanduser('~/.claude.json')) as f:
    data = json.load(f)
home = os.path.expanduser('~')
template = {}
for key in ['mcpServers', 'autoUpdates', 'teammateMode']:
    if key in data:
        template[key] = data[key]
s = json.dumps(template, indent=2)
s = s.replace(home, '\$HOME')
print(s)
" > "$REPO_DIR/config/claude.json.template"
echo "  config/claude.json.template"

# Tier 5: Plugin manifest from settings.json
python3 -c "
import json, os
with open(os.path.expanduser('~/.claude/settings.json')) as f:
    data = json.load(f)
for plugin, enabled in sorted(data.get('enabledPlugins', {}).items()):
    status = 'enabled' if enabled else 'disabled'
    print(f'{status} {plugin}')
" > "$REPO_DIR/config/plugins.txt"
echo "  config/plugins.txt"

echo ""
echo "Export complete. Review with 'git diff', then commit."
