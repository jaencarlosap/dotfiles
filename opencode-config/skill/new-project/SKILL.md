---
name: new-project
description: Use when starting from nothing: create a new app, API, CLI or service, set up a repo, scaffold with npm create / vite / next / cargo new / go mod init / uv. Covers checking the toolchain first, running the official generator NON-INTERACTIVELY (a prompt hangs the agent), proving the skeleton runs before any custom code, and one-change-at-a-time order. Not for an existing project. Triggers in Spanish too: "crea un proyecto nuevo", "desde cero", "arranca un repo", "monta un servidor/app/API".
---

# New project

Creating a project is where a small model loses the most time, and it is always
the same failure: **many files written before anything has been run once.** Then
the first command fails, and there is no way to tell which of the ten files is
wrong.

The order below exists to make every failure land on **one** change.

## 1. Check the toolchain BEFORE anything else

A missing or wrong-version toolchain is the single most common cause of a
scaffold that "keeps failing". One call:

```bash
command -v node npm go cargo python3 uv docker 2>/dev/null; node -v; go version
```

If what the task needs is not there, **stop and say so**. Do not work around it
by hand-writing what the generator would have produced.

## 2. Use the official generator — never hand-roll the skeleton

Writing `package.json`, `go.mod`, `Cargo.toml`, a lockfile or a bundler config
from memory means inventing version numbers and keys. That is the guessing this
setup exists to prevent.

**Confirm the current invocation before running it** — scaffolders change and
the one you remember may be deprecated (`create-react-app` is the classic
example). One lookup is enough:

```bash
web.sh search "official way to create a new <framework> project <year>"
docs.sh npm <generator>      # does it exist, what is the current version
<generator> --help           # the flags THIS version accepts
```

| Stack | Shape of the command (verify the flags first) |
| --- | --- |
| Node app | `npm create <tool>@latest <dir> -- --template <t>` |
| Go | `go mod init <module-path>` |
| Rust | `cargo new <dir>` |
| Python | `uv init <dir>` or `python3 -m venv .venv` |

## 3. Non-interactive, always

A generator that asks a question **hangs**: you are not a terminal, nothing
answers, and the tool call dies on timeout. That looks exactly like "the command
did nothing" — and then you retry it, and it hangs again.

- Pass the answers as flags: `--yes`, `-y`, `--template`, `--no-git`, `--force`.
- If a command hangs with no output, assume a prompt. Re-run with `--help` and
  find the flag that supplies the answer. Do not re-run it unchanged.

## 4. Prove the skeleton runs — before one line of your own code

```bash
cd <dir> && <install> && <build or run> && <test>
```

This is the moment to fix problems, while the only thing that exists is what the
generator produced. If the empty skeleton does not run, nothing you add will.

Then make it a baseline you can go back to:

```bash
git init -q 2>/dev/null; git add -A && git commit -qm "chore: scaffold" && git log --oneline -1
```

## 5. Only now, one feature at a time

For each piece: write it → run the build/test → commit. Never two features
between two runs of the test. If a run fails, the cause is in the last change —
that is the entire point of this order.

Follow the file rules you already have: check whether a file exists before
creating it, extend rather than duplicate, no placeholder and no TODO.

## 6. If it fails twice, stop scaffolding

Do not delete the directory and start over — you will hit the same wall. Load
the **`unstick`** skill: read the unfiltered error, name it, look the message up
with `web.sh search`, and change approach.

Deleting and re-running the generator is not a different approach.
