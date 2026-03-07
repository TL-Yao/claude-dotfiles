# Global Learnings
<!-- last-cleanup: 2026-03-08 -->

Cross-project learnings that apply beyond any single project.
Before adding a new entry, grep for similar entries first.

Format: [date] category | status

---

## 2026-03-08 hooks | active

**Summary**: Claude Code prompt hook `{ok: false}` does not grant Claude a new turn — use command hook exit code 2 instead
**Details**: Prompt hooks returning `{ok: false, reason: "..."}` send feedback but don't actually let Claude continue working (known bug #20221, closed as Not Planned). Command hooks with exit code 2 + stderr is the only reliable mechanism for blocking Stop/SubagentStop events and continuing the conversation. Also: command hooks read input from stdin (not $ARGUMENTS), and Stop decision uses exit code 2 (not JSON `{"decision": "block"}`).
**Action**: Always use `type: "command"` with exit code 2 for Stop hooks that need to block. Never use prompt hooks for blocking Stop events.
**Occurrences**: 1
**Projects**: skillPlayground

