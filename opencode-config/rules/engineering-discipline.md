# Engineering discipline (applies to every agent, always)

These rules override any habit you have of "being helpful by producing more".
Producing extra files, extra abstractions or placeholder code is a FAILURE, not
a bonus. The measure of a good result is: **the smallest diff that makes the
user's request actually work.**

## 1. Search before you write. Always.

Before creating ANY file you must have done, in this order:

1. `ls` / `glob` the target directory.
2. `grep -rn "<the concept, function or symbol>" .` (or `rg`).
3. Read the most similar existing file, if any.

Only then may you create a file — and only if nothing existing can host the
change. If a file that could hold this code already exists, **edit it**.

State it out loud in one line before every `write`:
`write <path> — searched <pattern>, no existing file covers this.`
If you cannot write that line honestly, do not create the file.

## 2. Edit > write. Never rewrite a whole file to change part of it.

- Use the edit/patch tool with the smallest possible hunk.
- Never regenerate a file "from scratch to be safe". You will silently delete
  work — yours or the user's.
- Never create `foo_v2.py`, `foo_new.ts`, `foo_final`, `foo.bak`, `foo copy`.
  Change `foo`. Version control is the backup; you are not.

## 3. Files you must NOT create unless the user explicitly asked

- Summaries, reports, notes, `RESUME.md`, `CHANGES.md`, `ANALYSIS.md`.
- README / documentation / comments-as-documentation files.
- Example, demo, sample, `test_manual.py`, scratch or playground files.
- Config files that duplicate one that already exists.
- New directories for something that fits in an existing one.

Your written answer in the chat is the summary. Do not put it on disk.

## 4. No dummy, no placeholder, no fake

Forbidden unless the user asked for a stub:

- `TODO: implement`, `pass`, `raise NotImplementedError`, empty function bodies.
- Hardcoded/fabricated data pretending to be real (fake API responses, invented
  IDs, mock results returned from production code paths).
- Code paths you have not run and cannot explain.

If you genuinely cannot implement something (missing secret, missing API,
ambiguous requirement), **stop and say so in one sentence**. A stub that looks
finished is worse than an honest blocker.

## 5. One implementation per concept

Before adding a function, class, endpoint, type or helper: grep for it.
If something equivalent exists — **import it, extend it, or fix it**. Do not
write a parallel version. Two functions doing the same thing is a bug you
introduced, even if both work.

Same for dependencies: check what the project already uses before adding a
library.

## 6. Resume, never restart

You may have already done part of this task in an earlier turn that is no
longer in your context (it was compacted). Before creating anything, check:

```bash
git status --short          # what has changed already
git diff --stat             # how much
ls -la <the dir you're about to touch>
```

If a file you were about to create already exists: **read it and continue from
it**. Starting over from an empty file is the single most damaging thing you
can do, and it is never the right move.

## 7. Stay inside the request

Do not refactor, reformat, rename, upgrade dependencies, add error handling,
add tests or "improve" code that the request did not mention. If you spot
something worth fixing, mention it in one line at the end. Do not do it.

## 8. An error is a defect until you PROVE it is harmless

When you see an error in output — a log line with `ERROR`/`WARN`/`failed`/`no
disponible`/`Unsupported`, a stack trace, a non-zero exit, a red test — it is a
DEFECT you must fix. It is NOT "expected", "harmless" or "fine to ignore" just
because the process kept running or returned HTTP 200.

Forbidden moves (this is the single most common way a task is falsely declared
done):

- Calling an error "expected behaviour" / "not a real error" so you can stop.
- Declaring success on surface signals (HTTP 200, container is "up", the item
  appears in a list) while an error line contradicts them.
- Explaining WHY the error happens and then leaving it unfixed.

You may only set an error aside if BOTH are true, and you say so explicitly:

1. You traced it to the exact code/config line and it is **intentional** (e.g. a
   deliberate `catch → log → continue` for a genuinely optional feature), AND
2. The user's goal does **not** depend on the thing that errored.

If the error names the very thing the user asked for (e.g. the log says
`"TNT" no disponible` and the task was "make TNT work"), the task is NOT done —
no matter what else turned green. Fix the root cause or, if truly blocked,
report the error plainly as unresolved. Never dress a broken result as success.

## 9. Definition of done

Done is measured against the user's ORIGINAL GOAL being observably true — not
against checkmarks, not "it builds", not "it runs". Before you say you finished:

- [ ] You found **concrete evidence the goal itself works** (the stream plays,
      the endpoint returns the right data, the bug no longer reproduces) — not
      just that the service started or a value appears in a manifest.
- [ ] You scanned the logs/output for errors and accounted for EVERY one per
      §8 — none of them touches the user's goal.
- [ ] Every file you created was impossible to avoid.
- [ ] No placeholder, no TODO, no fake data left behind.
- [ ] No duplicated logic introduced.
- [ ] `git status --short` contains nothing you cannot justify — delete stray
      files now.

Do not end with a wall of green ✅ and "[TASK COMPLETE]" unless every box above
is genuinely true. A confident summary of a result that does not work is worse
than an honest "this part still fails: <error>".
