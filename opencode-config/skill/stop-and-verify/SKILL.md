---
name: stop-and-verify
description: Use when you are about to state or write something you have not seen this session — an API signature, CLI flag, config key, import path, version, URL, file path — or to claim that something "does not exist" or "is not supported". Gives the stop signals, what counts as evidence, the cheapest-first checks, and how to word an answer you could not verify. Not for language syntax, and not for tools already in your tool list. Triggers in Spanish too: "no lo supongas", "verifica", "estas seguro", "no te lo inventes", "que version es".
---

# Stop and verify

You are a small model. You reason well and you **recall badly**. When you do
not know an exact name, you do not feel a gap — you produce a plausible
invention with full confidence. That is the single biggest source of broken
output in this setup, and it is not fixed by thinking harder. It is fixed by
looking, once, at the cheapest source that can answer.

A lookup costs seconds. A hallucinated API costs the whole task.

## 1. The stop signals

Stop the moment any of these is true. They are the tells, not vague feelings:

- You are about to type an identifier and cannot say **where you saw it**.
- You are choosing between two spellings (`--dry-run` vs `--dryrun`,
  `enabled` vs `enable`) and picking "the one that looks right".
- You are about to write a version number, a release date, a URL, a port or a
  benchmark figure from memory.
- You are about to say "X is not supported", "there is no way to do Y" or "the
  library does not have Z". A negative claim needs the same evidence as a
  positive one — and it is the claim that most often turns out wrong.
- The task mentions a library, framework or CLI you have not read in this
  session.
- You are about to run something destructive, touch auth/crypto, money, a
  schema migration, or write outside the repo.

If none of these is true, keep working. Stopping to look up a `for` loop is a
waste of a turn.

## 2. What counts as evidence

Only these. Everything else is a guess wearing a confident tone.

- A `file:line` you read this session.
- The output of a command you ran this session.
- A documentation page you fetched this session, with its URL.
- A line in `.agent/progress.md` under `# VERIFIED FACTS` that names its source.

Your own memory is **not** evidence for anything in §1. Neither is "it is the
obvious name".

## 3. Cheapest first — stop at the first rung that answers

| # | Rung | Use it for |
|---|------|-----------|
| 0 | This conversation, `.agent/progress.md`, `AGENTS.md` | anything already established. Free. |
| 1 | `grep -rn "Symbol" . --include="*.go"` | project shape, conventions, an existing call site. A call site beats docs: it compiles today, against the version actually installed. |
| 2 | The dependency on disk: `go doc pkg.Sym`, `node_modules/pkg/**/*.d.ts`, `python -c "help(pkg.x)"` | exact signatures of what is installed. |
| 3 | `<cmd> --help`, `<cmd> <sub> --help`, `man <cmd>` | flags and subcommands. |
| 4 | A 3-line probe you write and run | "what does this actually return". Faster and more truthful than any doc. |
| 5 | `docs.sh npm\|py\|rs\|go\|mdn\|wiki <name>` | does a package exist, what version is current, where its docs are. |
| 6 | The web — **load the `web-research` skill** | anything the machine cannot answer: version-specific behaviour, error messages, upstream changes, docs for something not installed here. |

Rungs 1–4 are almost always enough for project work. Rung 6 is for the rest,
and it is a real option here — do not claim you have no way to check.

## 4. Budget — verifying is not free either

- **One lookup answers one question.** Never open a browsing loop.
- **Two lookups maximum before you attempt the code.** Then write it and let
  the compiler, the LSP and the tests tell you the rest. That oracle is faster
  and more accurate than more reading.
- Never look up what the error message hands you in two seconds.
- **No budget — always verify first:** destructive commands, migrations,
  auth/crypto, money, deletions, anything outside the repo. A wrong guess there
  fails silently and expensively.

## 5. Two mistakes that look like caution

**Do not "verify" your own tools.** Every tool you can call is listed in your
prompt with its parameters. That list *is* the source. Calling one is never
guessing, and a tool you can see is never missing. Refusing to call
`jiraAdmin_confluence-search` "because I cannot be sure it exists", and then
telling the user no MCP server is configured, has actually happened here. If
you are unsure which tool fits, call the most likely one and read the error.

**Do not stop for what you genuinely know.** Language syntax, control flow,
standard algorithms, and anything visible in this conversation: write it.

## 6. Record what you learned

When a lookup produces a fact you will need again, append it to
`.agent/progress.md`:

```markdown
# VERIFIED FACTS

- opencode permission key is `skill` (not `skills`) — source: opencode debug config
```

Context gets compacted; that file does not. Looking the same signature up three
times is how a fast model becomes a slow one.

## 7. When you could not verify it

Say it in one line and move on. A precise "unknown" is a useful answer; an
invented API that only compiles in your head is not.

> `pkg.DoThing()` does not exist in the installed version (checked:
> `go doc pkg | grep DoThing`); the closest match is `pkg.Do(ctx, opts)`.

> The default timeout is **unverified** — not in `--help`, not in the repo, and
> the docs page did not state it. I used 30s explicitly so it does not matter.

Finish everything that does not depend on the unknown, mark the one hole, and
hand it over. Never fill the hole with a plausible name.
