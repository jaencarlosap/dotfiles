# AGENTS.md

Project context for opencode agents. opencode loads this file automatically,
so anything here is available to `auto`/`analyze` without you repeating it.
Keep it short and factual — it competes for the small model's context.

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
