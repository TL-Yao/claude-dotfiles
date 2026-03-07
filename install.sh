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
for cmd in node npm python3 rsync; do
  command -v "$cmd" >/dev/null || { echo "Error: $cmd not found"; exit 1; }
done
NODE_VER=$(node -v | sed 's/v//' | cut -d. -f1)
[ "$NODE_VER" -ge 18 ] || { echo "Error: Node.js >= 18 required (got $NODE_VER)"; exit 1; }

echo "Installing Claude Code config ($([ "$FORCE" = true ] && echo "FORCE overwrite" || echo "merge mode"))..."
echo ""

# Detect shell RC file
case "${SHELL:-/bin/bash}" in
  */zsh)  SHELL_RC="$HOME/.zshrc" ;;
  */bash) SHELL_RC="$HOME/.bashrc" ;;
  */fish) SHELL_RC="$HOME/.config/fish/config.fish" ;;
  *)      SHELL_RC="$HOME/.profile" ;;
esac

# 1. Create directory structure
mkdir -p "$CLAUDE_DIR"/{agents,skills,plugins,mcp-servers/reader-mcp,learnings,hooks}

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
  python3 << PYEOF - "$CLAUDE_DIR" "$REPO_DIR"
import json, sys

claude_dir = sys.argv[1]
repo_dir = sys.argv[2]

with open(f"{claude_dir}/settings.json") as f:
    existing = json.load(f)
with open(f"{repo_dir}/config/settings.json") as f:
    incoming = json.load(f)
for plugin, enabled in incoming.get("enabledPlugins", {}).items():
    if plugin not in existing.get("enabledPlugins", {}):
        existing.setdefault("enabledPlugins", {})[plugin] = enabled
# Fields that should always be overwritten from repo (not just added-if-missing)
OVERWRITE_FIELDS = {"hooks", "permissions", "env", "skipDangerousModePermissionPrompt"}
for key, val in incoming.items():
    if key == "enabledPlugins":
        continue
    if key in OVERWRITE_FIELDS:
        existing[key] = val  # always take repo version
    elif key not in existing:
        existing[key] = val  # add new fields only
with open(f"{claude_dir}/settings.json", "w") as f:
    json.dump(existing, f, indent=2)
    f.write("\n")
print("  settings.json: merged")
PYEOF
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
  BUILD_LOG="$CLAUDE_DIR/mcp-servers/reader-mcp/build.log"
  if (cd "$CLAUDE_DIR/mcp-servers/reader-mcp" && npm install && npm run build) > "$BUILD_LOG" 2>&1; then
    echo "  reader-mcp: build complete"
  else
    echo "  reader-mcp: BUILD FAILED — see $BUILD_LOG"
  fi
else
  echo "  reader-mcp: source updated, dist/ exists (skip build)"
fi

# 7. ~/.claude.json — merge mcpServers
TEMPLATE_FILE=$(mktemp)
sed "s|\\\$HOME|$HOME|g" "$REPO_DIR/config/claude.json.template" > "$TEMPLATE_FILE"
if [ "$FORCE" = true ] || [ ! -f "$HOME/.claude.json" ]; then
  if [ -f "$HOME/.claude.json" ] && [ "$FORCE" = true ]; then
    # Force mode: merge into existing (don't destroy auto-generated fields)
    python3 << 'PYEOF' - "$TEMPLATE_FILE" "$HOME/.claude.json"
import json, sys

template_path = sys.argv[1]
target_path = sys.argv[2]

with open(template_path) as f:
    incoming = json.load(f)
with open(target_path) as f:
    existing = json.load(f)
for key in incoming.get("mcpServers", {}):
    existing.setdefault("mcpServers", {})[key] = incoming["mcpServers"][key]
for key, val in incoming.items():
    if key != "mcpServers":
        existing[key] = val
with open(target_path, "w") as f:
    json.dump(existing, f, indent=2)
    f.write("\n")
print("  .claude.json: force-merged mcpServers + settings")
PYEOF
  else
    cp "$TEMPLATE_FILE" "$HOME/.claude.json"
    echo "  .claude.json: installed (new)"
  fi
else
  python3 << 'PYEOF' - "$TEMPLATE_FILE" "$HOME/.claude.json"
import json, sys

template_path = sys.argv[1]
target_path = sys.argv[2]

with open(template_path) as f:
    incoming = json.load(f)
with open(target_path) as f:
    existing = json.load(f)
for key in incoming.get("mcpServers", {}):
    existing.setdefault("mcpServers", {})[key] = incoming["mcpServers"][key]
for key, val in incoming.items():
    if key != "mcpServers" and key not in existing:
        existing[key] = val
with open(target_path, "w") as f:
    json.dump(existing, f, indent=2)
    f.write("\n")
print("  .claude.json: merged mcpServers")
PYEOF
fi
rm -f "$TEMPLATE_FILE"

# 8. Learnings — copy if missing, append-only merge if exists
if [ "$FORCE" = true ] || [ ! -f "$CLAUDE_DIR/learnings/LEARNINGS.md" ]; then
  cp "$REPO_DIR/learnings/LEARNINGS.md" "$CLAUDE_DIR/learnings/" 2>/dev/null || true
  echo "  learnings: installed"
else
  python3 << 'PYEOF' - "$CLAUDE_DIR" "$REPO_DIR"
import sys, re

claude_dir = sys.argv[1]
repo_dir = sys.argv[2]

local_path = f"{claude_dir}/learnings/LEARNINGS.md"
repo_path = f"{repo_dir}/learnings/LEARNINGS.md"

with open(local_path) as f:
    local = f.read()
with open(repo_path) as f:
    repo = f.read()

# Extract entries by their ## heading + Summary line
def extract_entries(text):
    entries = {}
    for match in re.finditer(r'(## \d{4}-\d{2}-\d{2} .+?\n(?:(?!## \d{4}).)*)', text, re.DOTALL):
        block = match.group(1)
        summary_match = re.search(r'\*\*Summary\*\*: (.+)', block)
        if summary_match:
            entries[summary_match.group(1).strip()] = block
    return entries

local_entries = extract_entries(local)
repo_entries = extract_entries(repo)

new_entries = []
for summary, block in repo_entries.items():
    if summary not in local_entries:
        new_entries.append(block)

if new_entries:
    with open(local_path, 'a') as f:
        for entry in new_entries:
            f.write('\n' + entry)
    print(f"  learnings: merged {len(new_entries)} new entry(ies)")
else:
    print("  learnings: already up to date")
PYEOF
fi

# 9. Hooks — copy all hook scripts
HOOKS_ADDED=0
for hook_script in "$REPO_DIR/hooks/"*.sh; do
  [ -f "$hook_script" ] || continue
  name=$(basename "$hook_script")
  if [ "$FORCE" = true ] || [ ! -f "$CLAUDE_DIR/hooks/$name" ]; then
    cp "$hook_script" "$CLAUDE_DIR/hooks/"
    chmod +x "$CLAUDE_DIR/hooks/$name"
    HOOKS_ADDED=$((HOOKS_ADDED + 1))
  fi
done
echo "  hooks: added $HOOKS_ADDED new"

# 10. Binary dependencies for LSP plugins
echo ""
echo "Checking binary dependencies..."

# TypeScript LSP needs vtsls
if ! command -v vtsls >/dev/null 2>&1; then
  echo "  Installing @vtsls/language-server + typescript..."
  NPM_PREFIX="${HOME}/.npm-global"
  # Only override npm prefix if it's the system default (avoid breaking nvm/n)
  CURRENT_PREFIX=$(npm config get prefix 2>/dev/null || echo "")
  if [ "$CURRENT_PREFIX" = "/usr" ] || [ "$CURRENT_PREFIX" = "/usr/local" ]; then
    mkdir -p "$NPM_PREFIX"
    npm config set prefix "$NPM_PREFIX" || true
  else
    NPM_PREFIX="$CURRENT_PREFIX"
  fi
  if npm install -g @vtsls/language-server typescript; then
    echo "  vtsls: installed to $NPM_PREFIX/bin/"
  else
    echo "  vtsls: FAILED — run 'npm install -g @vtsls/language-server typescript' manually"
  fi
  # Ensure PATH includes npm-global
  if [ "$NPM_PREFIX" = "$HOME/.npm-global" ] && ! grep -q 'npm-global/bin' "$SHELL_RC" 2>/dev/null; then
    echo "export PATH=\"\$HOME/.npm-global/bin:\$PATH\"" >> "$SHELL_RC"
    echo "  PATH: added ~/.npm-global/bin to $SHELL_RC"
  fi
else
  echo "  vtsls: already installed ($(command -v vtsls))"
fi

# Rust analyzer needs rustup + rust-analyzer component
if ! command -v rust-analyzer >/dev/null 2>&1; then
  if command -v rustup >/dev/null 2>&1; then
    echo "  Installing rust-analyzer via rustup..."
    if rustup component add rust-analyzer; then
      echo "  rust-analyzer: installed"
    else
      echo "  rust-analyzer: FAILED — run 'rustup component add rust-analyzer' manually"
    fi
  else
    echo "  rust-analyzer: SKIPPED — rustup not installed"
    echo "    Install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    echo "    Then: rustup component add rust-analyzer"
  fi
  # Ensure PATH includes cargo bin
  if [ -d "$HOME/.cargo/bin" ] && ! grep -q 'cargo/bin' "$SHELL_RC" 2>/dev/null; then
    echo "export PATH=\"\$HOME/.cargo/bin:\$PATH\"" >> "$SHELL_RC"
    echo "  PATH: added ~/.cargo/bin to $SHELL_RC"
  fi
else
  echo "  rust-analyzer: already installed ($(command -v rust-analyzer))"
fi

# Excel MCP needs uv/uvx
if ! command -v uvx >/dev/null 2>&1; then
  echo "  Installing uv (for Excel MCP server)..."
  if curl -LsSf https://astral.sh/uv/install.sh | sh; then
    echo "  uv/uvx: installed"
  else
    echo "  uv/uvx: FAILED — run 'curl -LsSf https://astral.sh/uv/install.sh | sh' manually"
  fi
else
  echo "  uv/uvx: already installed ($(command -v uvx))"
fi

# 11. Summary + smart verification
echo ""
echo "=== Installation complete ($([ "$FORCE" = true ] && echo "force" || echo "merge") mode) ==="
echo ""
"$REPO_DIR/verify.sh" || true
echo ""
echo "Restart Claude Code to activate all changes."
