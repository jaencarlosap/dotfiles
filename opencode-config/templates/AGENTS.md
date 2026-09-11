# AGENTS.md

Project context for opencode agents. opencode loads this file automatically, on
every turn, so anything here is available without you repeating it — and it
survives compaction, which is what makes it valuable.

Keep it short and factual: it competes for the model's context. Measured with
the real tokenizer: 5.167 chars = 1.423 tokens per turn for the AGENTS.md of
`stremio-iptv-addon`. It pays for itself if it prevents ONE blind exploration
(that one cost 40 calls and produced no answer).

Write it in ENGLISH, like `rules/` and the skills. Not because English is a
better language for a model — benchmarks do not show that — but because the
rest of what the model reads (opencode's own prompt, the rules, the guard
messages) is English, and mixing languages inside one prompt is what measurably
degrades a local model. Keep identifiers verbatim: log `type` values, container
names and commands are not translated.

This is the ONLY config file for the project. The state of the current task
lives in `.agent/progress.md` (gitignored), which is a different thing. Do not
create `.agents/`, `.opencode/progress.md` or `NOTES.md`: the guard blocks them.

## What goes here (and what does not)

What an agent CANNOT work out by reading the code:

- where the real state lives and HOW to query it — an actual command, not
  "there is a database"
- which service is which, which port, which container
- the traps already paid for: the bug that cost three sessions, and why it
  raised no error
- the files NOT to read whole because they are huge

What does NOT go here: anything visible in the code, project history, plans.

## What this project is

<!-- One or two sentences: what it does, main language/framework. -->

## Commands (use these exact commands to verify your work)

- Build:    `__BUILD__`
- Test:     `__TEST__`
- Lint/fmt: `__LINT__`
- Run:      <!-- how to start the app locally -->

Always run the build + test above before saying a task is done.

## Conventions

<!-- Naming, error handling, logging, folder layout the model must follow.
     e.g. "errors are wrapped with fmt.Errorf(...%w)", "no global state",
     "tests live next to the file as *_test.go". -->

## Do NOT

<!-- Landmines specific to this repo.
     e.g. "do not edit generated files in /gen", "do not bump deps",
     "do not touch the migration files in /db/migrations". -->
