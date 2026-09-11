---
name: unstick
description: Use the moment something has failed twice, a command returns nothing or the same thing again, or you are about to retry after an error — a build, install, test, command or search. Gives the procedure: read the UNFILTERED error, name what it means, cut the problem down, look the message up, and change approach instead of re-running. Use also when the environment says "BLOCKED (loop)". Triggers in Spanish too: "sigue fallando", "no funciona", "se queda en bucle", "da el mismo error", "no avanza".
---

# Unstick

You are here because something failed and doing it again did not help. Repeating
is not persistence: at temperature 0.6 with the same input you get the same
output. Only a **change of approach** moves this forward.

The rule: **second identical failure = stop executing, start diagnosing.** The
third attempt is blocked by the environment anyway.

## 1. See the real error — most loops die right here

Re-run the command **once, with nothing filtering it**:

- no `| grep`, no `| head`, no `| tail` on the first read
- no `2>/dev/null`, no `-q`, no `--silent`

Why this is the first step and not the third: errors go to **stderr**. Your own
`2>/dev/null` or `| grep` turns an *error* into an *empty result*, and an empty
result looks exactly like "no matches found" — so you rewrite the query and
retry forever. Two real loops in this setup started exactly this way
(`webfetch ... 2>/dev/null | grep`, `ripgrep --help 2>&1 | grep -i max`).

If the output is genuinely huge: `cmd 2>&1 | tail -40`. Never drop stderr.

## 2. Say what the error means, in one sentence

You cannot fix what you have not named. Match the message:

| Message | What it actually means | Check it with |
| --- | --- | --- |
| `command not found` | that binary does not exist here (or has another name: `ripgrep` → `rg`) | `command -v <name>` |
| `No such file or directory` | wrong path or wrong working directory | `pwd`, `ls -la <dir>` |
| `Cannot find module` / `ModuleNotFoundError` / `no required module provides` | dependency not installed, or you are in the wrong project root | `ls node_modules/<pkg>`, `pip show <pkg>`, `go list -m all \| grep <pkg>` |
| `undefined: X`, `has no attribute`, type errors on a library call | the API is not what you assumed — usually a version difference | version first, then docs **for that version** |
| `permission denied` | not yours to write, or the file is not executable | `ls -l`, `chmod +x`; if it needs `sudo`, stop and ask |
| `EADDRINUSE`, `address already in use` | something is already listening on that port | `lsof -i :<port>` |
| `connection refused` / timeout | the service is not up, or wrong host/port | start it, then retry once |
| `SyntaxError` / parse error with a line number | your own last edit | read that line |
| killed / exit 137 | out of memory | smaller input |

If the message names a file and a line, **read that line** before anything else.

## 3. Cut the problem in half

Reduce until the error is trivially reproducible:

- Run the failing piece **alone**, outside the pipeline, the script, the test.
- Smallest input that still fails. One variable changed at a time.
- Does it fail in a clean directory? With a fresh file? Without your last edit?

A minimal repro usually *is* the diagnosis.

## 4. If the machine cannot tell you, look it up

An error message is the single best search query you will ever have — it is
exact, and someone else has already hit it.

1. Clean the message: drop absolute paths, line numbers, hashes, timestamps and
   your own project names. Keep the wording and the identifiers.
2. Add the tool and version: `vite 6`, `go 1.24`, `postgres 17`.

```bash
web.sh search "\"Cannot find module 'vite'\" npm run dev vite 6"
docs.sh npm vite            # is the package real, what version is current
web.sh read <the official docs or issue URL from the results>
```

Load the **`web-research`** skill for which sources count and how much to read.
When in doubt about whether to look something up at all, that is
**`stop-and-verify`**.

## 5. Change the approach — not the flag

| Not a new attempt | A new attempt |
| --- | --- |
| Same command, different `grep`/`--flag`/quotes | A different tool or mechanism entirely |
| Same install command again | Read the installer's actual error, fix the cause (missing toolchain, wrong node version) |
| Rewriting the same file the same way | Read the file first, then edit the specific line |
| Retrying a network call | Check the service is up, then retry once |

If you cannot name what you are doing *differently*, you are not doing anything
differently.

## 6. Budget, and when to stop

- **Three diagnostic actions per error.** Then it is either fixed, or you
  report.
- Append what you learned to `.agent/progress.md` under `# VERIFIED FACTS`,
  with the command that proved it. The next turn must not repeat this.
- Never make an error disappear by deleting code, stubbing the function,
  swallowing the exception, or quietly switching to an easier task.

Report like this and stop — it is a good outcome, not a failure:

> `npm run dev` fails with `Cannot find module 'vite'`. `node_modules/vite` does
> not exist and `npm install` exits with EACCES on `~/.npm`. I tried a clean
> install and a cache clear. This looks like an npm cache owned by root; fixing
> it needs `sudo chown -R $(whoami) ~/.npm`, which I cannot run.
