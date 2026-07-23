---
description: Diagnose the current failure, fix root cause, then re-verify
agent: auto
---

Fix a failure. The failure to fix is: $ARGUMENTS
(If that is empty, first run the same detection as `/verify` to reproduce the
current failure, then fix that.)

Follow this loop — it is not optional:

1. **Reproduce.** Run the build/test and capture the exact error. If you cannot
   reproduce it, say so and stop; do not "fix" a problem you cannot see.
2. **Root cause, not symptom.** Read the failing `file:line` and the code
   around it. State in one sentence what is actually wrong before touching
   anything. Do not silence the error (no try/except pass, no `// nolint`, no
   deleting the assertion) — that is forbidden by the engineering rules.
3. **Smallest fix.** Edit only what the root cause requires. No refactors, no
   drive-by changes.
4. **Re-verify.** Re-run the same command. If it now passes, report
   `✅ FIXED — <one line: what was wrong, what you changed>`.
   If it still fails, go back to step 2 with the new error. Repeat until green
   or until you hit a genuine hard blocker (missing secret/permission), which
   you then state in one sentence.

Never report "fixed" without having re-run the check and seen it pass.
