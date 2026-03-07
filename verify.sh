#!/bin/bash
# Smart post-install verification — only shows what's still pending
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

PASS=0
FAIL=0
PENDING_PLUGINS=()
PENDING_COMMANDS=()

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

echo "Checking post-install status..."
echo ""

# 1. Claude Code binary
if command -v claude >/dev/null 2>&1; then
  pass "Claude Code installed"
else
  fail "Claude Code not installed"
  PENDING_COMMANDS+=("npm install -g @anthropic-ai/claude-code")
fi

# 2. Plugins — check enabled plugins from plugins.txt against installed_plugins.json
INSTALLED_PLUGINS="$CLAUDE_DIR/plugins/installed_plugins.json"
if [ -f "$REPO_DIR/config/plugins.txt" ]; then
  while IFS=' ' read -r status plugin || [ -n "${status:-}" ]; do
    [ "$status" != "enabled" ] && continue
    if [ -f "$INSTALLED_PLUGINS" ]; then
      if python3 -c "
import json, sys
with open('$INSTALLED_PLUGINS') as f:
    data = json.load(f)
sys.exit(0 if '$plugin' in data.get('plugins', {}) else 1)
" 2>/dev/null; then
        pass "Plugin: $plugin"
      else
        fail "Plugin: $plugin"
        PENDING_PLUGINS+=("$plugin")
      fi
    else
      fail "Plugin: $plugin"
      PENDING_PLUGINS+=("$plugin")
    fi
  done < "$REPO_DIR/config/plugins.txt"
fi

# 3. Marketplaces — check extraKnownMarketplaces from config/settings.json
KNOWN_MARKETPLACES="$CLAUDE_DIR/plugins/known_marketplaces.json"
if [ -f "$REPO_DIR/config/settings.json" ]; then
  EXPECTED_MARKETPLACES=$(python3 -c "
import json
with open('$REPO_DIR/config/settings.json') as f:
    data = json.load(f)
for k in data.get('extraKnownMarketplaces', {}):
    print(k)
" 2>/dev/null) || true

  for mp in $EXPECTED_MARKETPLACES; do
    if [ -f "$KNOWN_MARKETPLACES" ] && python3 -c "
import json, sys
with open('$KNOWN_MARKETPLACES') as f:
    data = json.load(f)
sys.exit(0 if '$mp' in data else 1)
" 2>/dev/null; then
      pass "Marketplace: $mp"
    else
      fail "Marketplace: $mp"
      # Marketplace is auto-registered when installing a plugin from it
    fi
  done
fi

# 4. Binaries
for bin_name in vtsls rust-analyzer uv; do
  cmd="$bin_name"
  # vtsls binary is actually vtsls (the package installs it as vtsls)
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "Binary: $bin_name"
  elif [ "$bin_name" = "vtsls" ] && [ -f "$HOME/.npm-global/bin/vtsls" ]; then
    pass "Binary: $bin_name (~/.npm-global/bin/)"
  else
    fail "Binary: $bin_name"
    case "$bin_name" in
      vtsls) PENDING_COMMANDS+=("npm install -g @vtsls/language-server typescript") ;;
      rust-analyzer) PENDING_COMMANDS+=("rustup component add rust-analyzer") ;;
      uv) PENDING_COMMANDS+=("curl -LsSf https://astral.sh/uv/install.sh | sh") ;;
    esac
  fi
done

# 5. Reader MCP build
if [ -f "$CLAUDE_DIR/mcp-servers/reader-mcp/dist/index.js" ]; then
  pass "Reader MCP: built"
else
  fail "Reader MCP: not built"
  PENDING_COMMANDS+=("cd ~/.claude/mcp-servers/reader-mcp && npm install && npm run build")
fi

# 6. Learnings directory
if [ -f "$CLAUDE_DIR/learnings/LEARNINGS.md" ]; then
  pass "Learnings: initialized"
else
  fail "Learnings: not initialized"
fi

# 7. Hooks
if [ -f "$CLAUDE_DIR/hooks/session-end-learnings.sh" ]; then
  pass "Hook: session-end-learnings"
else
  fail "Hook: session-end-learnings"
fi

# Summary
echo ""
TOTAL=$((PASS + FAIL))

if [ "$FAIL" -eq 0 ]; then
  echo "All $TOTAL checks passed. Nothing to do! ✅"
  exit 0
fi

echo "$FAIL pending action(s):"
echo ""

if [ ${#PENDING_PLUGINS[@]} -gt 0 ]; then
  echo "  Start a Claude Code session and run:"
  for p in "${PENDING_PLUGINS[@]}"; do
    echo "    /plugin install $p"
  done
  echo ""
fi

if [ ${#PENDING_COMMANDS[@]} -gt 0 ]; then
  echo "  Run in terminal:"
  for c in "${PENDING_COMMANDS[@]}"; do
    echo "    $c"
  done
  echo ""
fi

echo "  Then restart Claude Code to activate."
exit 1
