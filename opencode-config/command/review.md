---
description: Audit the current changes and report findings — does not fix them
agent: auto
---

Audit changes that are already written and report what is wrong with them. Do
NOT edit anything in this command: the deliverable is the list of findings.

**Load the `review-changes` skill first.** It has the method; this file only
sets the scope and the output.

Scope: $ARGUMENTS
(If that is empty, review the working tree: unstaged, staged and untracked.)

The two rules that decide whether this review is worth anything:

1. **Read the real diff before you say a word about it**, even if you already
   read it earlier in this session. The user edits files between turns.
2. **Every claim the diff makes about something outside itself gets checked
   against that thing** — a tool name against the server that registers it, a
   parameter against its schema, a model id against the server that serves it,
   a number against where it came from. A comment saying "verified" is a claim,
   not evidence.

Report, most severe first, and for each finding: `file:line`, one sentence on
what is wrong, the situation in which it bites, and the command or `file:line`
that proves it. Keep verified findings and unverified suspicions in separate
lists — never in the same bullet. If the risky part of the change turns out to
be correct, say so in one line with the evidence.

Finish with the one thing you would fix first. Do not fix it unless the user
asks.
