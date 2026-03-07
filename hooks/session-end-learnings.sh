#!/bin/bash
# Injects a learning evaluation reminder at session end
cat << 'EOF'
[Self-Evolution] Session ending. Evaluate:
1. Any non-trivial error solved? -> Log to project CLAUDE.md (project-specific) or ~/.claude/learnings/LEARNINGS.md (cross-project)
2. Any user correction or knowledge gap? -> Same as above
3. Any recurring pattern (3+ times)? -> Promote to global CLAUDE.md
Skip if nothing worth recording.
EOF
