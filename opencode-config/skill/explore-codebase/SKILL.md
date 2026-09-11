---
name: explore-codebase
description: Use when you have to change or debug code in a repository you have not read this session — an unfamiliar project, a new checkout, "where is X handled", "add this to the existing app". Covers finding the entry point, how it is built and tested, the conventions to copy, and the call site of the thing you are about to touch, with a fixed budget of commands and without dumping whole files into context. Triggers in Spanish too: "en este proyecto", "donde esta", "como funciona este repo", "añade esto al proyecto existente".
---

# Getting oriented in a repo

Two failure modes, and they are opposites. One is editing blind — inventing a
structure that does not match the project. The other is reading everything —
`cat` after `cat` until the context compacts and the goal is gone.

The way out of both: **learn the four things below, in about six commands, and
stop.**

## 1. The shape of it (one call)

```bash
ls -la && cat README.md 2>/dev/null | head -40 && ls */ 2>/dev/null | head -30
```

Also check for an `AGENTS.md` — in this setup it is the project's own briefing
and it beats anything you would infer.

## 2. How it is built, run and tested — from the build file, not from memory

The build file tells you the real commands. Read that one, whole:

```bash
cat package.json 2>/dev/null || cat Makefile 2>/dev/null || cat go.mod 2>/dev/null \
  || cat pyproject.toml 2>/dev/null || cat Cargo.toml 2>/dev/null
```

Write the build/test/run commands into `.agent/progress.md` under
`# VERIFIED FACTS`. You will need them at the end, and they are exactly what
gets lost when the context compacts.

## 3. The entry point

```bash
ls cmd/ src/ app/ 2>/dev/null; ls main.* index.* app.* server.* 2>/dev/null
grep -rn "func main\|if __name__\|createServer\|listen(" . --include="*.go" --include="*.py" --include="*.ts" --include="*.js" | head -10
```

One file read, from the top, is worth more than ten greps: the entry point shows
the wiring, the config style and the conventions in one go.

## 4. The place you are actually going to touch

This is the only deep dive, and it is narrow. Search by **behaviour**, not by
guessed file names:

```bash
grep -rn "<the endpoint, the message, the flag, the symbol>" . --include="*.<ext>" | head -20
```

Then read **that** file — with `sed -n '40,120p'` or `grep -n -A 20`, not `cat`
if it is over ~200 lines. Look for: how similar things are already done, the
error-handling style, the test right next to it.

An existing call site beats any documentation: it compiles today, against the
version actually installed.

## 5. Copy the conventions, do not import your own

Before writing anything, know: how errors are returned, how things are named,
how config is read, where tests live and what they are called, whether
dependency injection is used. New code that looks foreign is a defect even when
it works.

## 6. Budget

- **Six commands** to get oriented, then start working. If you are still
  reading, you are procrastinating with tools.
- Never `cat` a file over 200 lines; never echo a whole file into the chat.
- If the repo is genuinely large and the question is narrow, narrow the
  COMMAND, not the agent: one `grep -rn` with `| head -20` beats reading three
  files. There is no subagent to hand it to (`analyze` was removed 2026-09-07).
- Write what you learned to `.agent/progress.md`. Getting oriented twice in the
  same session is how a fast model becomes a slow one.
