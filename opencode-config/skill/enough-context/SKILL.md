---
name: enough-context
description: Use at the START of any task before writing code, to check whether you actually have the information needed to solve it — and to go get what is missing, from the repo, the disk or the internet, until you do. Gives the inventory (what this task needs), how to mark each fact KNOWN-with-source or UNKNOWN, how to resolve the unknowns cheapest-first ending in a web search, the budget that stops the research, and how to proceed on a stated assumption when a fact cannot be resolved. Triggers in Spanish too: "tienes la informacion necesaria", "investiga antes de empezar", "busca lo que falte", "no empieces sin", "consulta primero". Do NOT use it for a question you can answer in one or two sentences with no code, or for a task whose facts you already have.
---

# Do I have enough to solve this?

Answer that **before** you write code, not after the compiler tells you. Two
opposite failures cost real time here, and this gate exists to sit between them:

- **Starting without enough**: 200 lines against an API you imagined. Everything
  after the wrong assumption is wasted, including the debugging.
- **Never starting**: reading and searching things that would not have changed a
  single line. Research is not progress either.

The gate is one question per fact, and it has a hard exit.

## 1. Inventory: what does THIS task need?

One short list, written out. Not a plan — a list of **facts** the code depends
on. Typically 3 to 6 of these:

- Third-party names: function, method, class, parameter, return shape.
- CLI flags, subcommands, env var names, config keys, ports.
- Version-dependent behaviour and defaults.
- Project facts: where this lives, how it is built and tested, the conventions.
- The requirement itself: what "done" means, in one sentence.

If the list is empty, this gate does not apply — the task is language and logic.
Write it.

## 2. Mark every item: KNOWN (with a source) or UNKNOWN

A fact is KNOWN only if you can name where it came from **in this session**:
a `file:line` you read, a command output, a doc page you fetched, or a line in
`.agent/progress.md` under `# VERIFIED FACTS`.

"I am fairly sure it is called that" is UNKNOWN. Write it down as UNKNOWN. The
whole point of this step is that a small model cannot feel the difference between
knowing and guessing — so make it explicit on paper instead.

Then apply the only filter that matters:

> **Would a wrong answer here change the code I am about to write?**

- **No** → drop it. Do not research it. Version numbers in comments, background
  history, "how does it work internally" — none of that changes the code.
- **Yes** → it must be resolved before you write the line that depends on it.

## 3. Resolve the UNKNOWNs, cheapest first

Stop at the first rung that answers. Every rung is one command:

| # | Where | Command |
| --- | --- | --- |
| 1 | This repo — an existing call site beats any doc: it compiles today | `grep -rn "Symbol" . --include="*.ext" \| head -20` |
| 2 | The dependency on disk — the version actually installed | `go doc pkg.Sym`, `grep -rn "name" node_modules/pkg/**/*.d.ts`, `python3 -c "help(pkg.x)"` |
| 3 | The tool itself | `<cmd> --help \| grep -i <thing>` |
| 4 | A 3-line probe you run | fastest truth about "what does this return" |
| 5 | The registry | `docs.sh npm\|py\|rs\|go <name>` |
| 6 | **The internet** | `web.sh search "<exact identifiers>"` then `web.sh read <url>` |

Rung 6 is a real option on this machine — do not stop at 5 and guess. For how to
word the query and which sources count, load **`web-research`**. For a single
identifier mid-writing, that is **`stop-and-verify`**.

## 4. Budget: what stops the research

- **Two lookups per unknown.** Then either it is answered, or it goes to §5.
- **Six lookups for the whole gate.** If you are past that, you are not
  gathering context, you are avoiding the task.
- Never look up what the compiler, the LSP or a failing test will hand you in
  two seconds. Those are free oracles — use them instead of reading.
- **No budget at all** (verify first, always): destructive commands, schema
  migrations, auth or crypto, money, deletions, anything writing outside the
  repo. A wrong guess there fails silently and expensively.

Log every resolved fact in `.agent/progress.md`:

```markdown
# VERIFIED FACTS

- <the fact, one line> — source: <command, file:line, or URL>
```

That file survives compaction and the injected repo-state block puts it back in
front of you. Looking the same signature up twice is pure loss.

## 5. When a fact will not resolve

Do not stall, and do not paper over it. Pick one, explicitly:

**Proceed on a stated assumption** — when the unknown is contained and cheap to
change later:

> Assuming the endpoint is `POST /v1/refunds` (could not verify: no docs
> reachable, package not installed). It is in one place, `client.go:42`, so it
> is one line to fix if wrong.

**Stop and ask** — when being wrong is expensive or unrecoverable: a secret you
do not have, a destructive operation, a contradictory requirement, money.

Either way, say it in one line. An unverified fact carried silently into code is
the failure this whole setup exists to prevent.

## 6. Then go

Once every code-changing fact has a source, **stop gathering and build**. Write
the smallest piece, run it, and let the compiler and the tests answer the rest —
that loop is faster and more truthful than more reading.
