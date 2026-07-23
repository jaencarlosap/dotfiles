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

## 8. Definition of done

Before you say you are finished, verify:

- [ ] Every file you created was impossible to avoid.
- [ ] No placeholder, no TODO, no fake data left behind.
- [ ] No duplicated logic introduced.
- [ ] You ran something (test, build, script) that proves it works.
- [ ] `git status --short` contains nothing you cannot justify — if it lists a
      file you no longer need, delete it now.
