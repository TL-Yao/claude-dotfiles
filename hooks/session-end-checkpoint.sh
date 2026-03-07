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

# Check if session involved actual work worth reviewing
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)

HAS_WORK=false

if echo "$LAST_MSG" | grep -qi "has been updated successfully\|has been written\|committed\|created file\|modified.*file\|git commit\|git push\|export\.sh"; then
  HAS_WORK=true
fi

if [ "$HAS_WORK" = false ] && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  if grep -q '"tool":"Edit"\|"tool":"Write"\|"tool_name":"Edit"\|"tool_name":"Write"' "$TRANSCRIPT" 2>/dev/null; then
    HAS_WORK=true
  fi
fi

if [ "$HAS_WORK" = true ]; then
  echo "Self-evolution check: review if any learnings, memory updates, or dotfiles sync are needed for this session." >&2
  exit 2
fi

exit 0
