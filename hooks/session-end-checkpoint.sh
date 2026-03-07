#!/bin/bash
# Stop hook: remind Claude to do self-evolution checks before ending
# Command hooks receive JSON input on stdin
# Exit 0 = allow stop, Exit 2 + stderr = block stop and continue
set -uo pipefail

INPUT=$(cat)

# Check stop_hook_active — if true, Claude is already continuing from a previous block
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
if [ "$STOP_ACTIVE" = "true" ]; then
  exit 0
fi

echo "Self-evolution check: review if any learnings, memory updates, or dotfiles sync are needed. If nothing to do, say so briefly." >&2
exit 2
