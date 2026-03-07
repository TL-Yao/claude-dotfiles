#!/bin/bash
# Smart session-end checkpoint using decision format
# Reads $ARGUMENTS (JSON with transcript_path, last_assistant_message, etc.)
# Outputs {"decision": "approve"} or {"decision": "block", "systemMessage": "..."}

ARGS="$ARGUMENTS"

# If no arguments provided, approve (safe default)
if [ -z "$ARGS" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Extract last_assistant_message from $ARGUMENTS JSON
LAST_MSG=$(echo "$ARGS" | jq -r '.last_assistant_message // ""' 2>/dev/null || true)

# Anti-loop: if Claude already did the checkpoint, approve
if echo "$LAST_MSG" | grep -qi "session checkpoint complete\|self-evolution check"; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Check if session involved actual file modifications
# Look for indicators of real work in the last assistant message
HAS_WORK=false

# Check for tool usage indicators (Edit, Write, git commit, etc.)
if echo "$LAST_MSG" | grep -qi "has been updated successfully\|has been written\|committed\|created file\|modified.*file\|git commit\|git push\|export\.sh"; then
  HAS_WORK=true
fi

# Also check transcript if available for more reliable detection
TRANSCRIPT=$(echo "$ARGS" | jq -r '.transcript_path // ""' 2>/dev/null || true)
if [ "$HAS_WORK" = false ] && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  # Look for Edit/Write tool calls in transcript (these are definitive)
  if grep -q '"tool":"Edit"\|"tool":"Write"\|"tool_name":"Edit"\|"tool_name":"Write"' "$TRANSCRIPT" 2>/dev/null; then
    HAS_WORK=true
  fi
fi

if [ "$HAS_WORK" = true ]; then
  jq -n '{
    "decision": "block",
    "reason": "Session involved code or config changes.",
    "systemMessage": "Before stopping: review your conversation for any Self-Evolution habits (learnings, dotfiles sync, memory updates) that apply but were not completed. When done, end your message with '\''Session checkpoint complete'\''."
  }'
else
  echo '{"decision": "approve"}'
fi

exit 0
