---
name: web-research
description: Use when a fact cannot be established from this machine and you need the internet: docs for a library not installed here, a signature or config key you could not find on disk, the meaning of an error message, what changed in a version. Covers `web.sh search`, `web.sh read`, `docs.sh`, how to word the query, which sources count, and how much to read. Use after the local checks came up empty. Triggers in Spanish too: "busca en internet", "consulta la documentacion", "mira la web", "documentacion oficial".
---

# Web research

There **is** web access from this machine — through `bash`, not through a
dedicated tool. Two commands, both already on your `PATH`:

```bash
web.sh search "opencode SKILL.md frontmatter fields"   # titles + URLs + excerpts
web.sh read https://opencode.ai/docs/skills/           # that page as plain text
```

`web.sh search` uses the same backend as opencode's own web search (Exa) and
falls back to DuckDuckGo (titles and URLs only) if it fails. `web.sh read`
strips a page down to its `<main>`/`<article>` text and truncates it — raise the
limit with `WEB_READ_CHARS=12000` only if the part you need got cut off.

They cost **zero prompt tokens** until you call them, which is why they are shell
commands and not tools. Do not look for a `websearch` tool: there is none.

## 1. Before you come here

The web is rung 6. Do not skip 1–5 — they are faster and they describe the
version actually installed:

```bash
grep -rn "SymbolName" . --include="*.ts" | head -20   # an existing call site
grep -rn "name" node_modules/pkg/dist/*.d.ts | head   # signatures on disk
<cmd> --help | grep -i <thing>                        # flags
docs.sh npm express        # registry: latest version, repo, types, docs URL
```

`docs.sh npm|py|rs|go|mdn|wiki <name>` answers "does this exist / what is the
current version / where are its docs" in one call, with no search engine in the
middle. Prefer it over `web.sh search` whenever the question is about a package.

## 2. How to word the query

You are searching for a document, not asking a person a question.

- Put the **exact identifiers** in the query: the package name, the symbol, the
  flag, the config key, the literal error string.
- Add the **version** when behaviour depends on it: `express 5 res.status types`.
- Prefer the vocabulary of the docs to your own: `frontmatter fields`, not
  "what do I put at the top of the file".
- One question per search. If you need two facts, run two searches.

```bash
web.sh search "opencode config permission keys skill allow"
web.sh search "\"context deadline exceeded\" grpc-go client keepalive"
```

## 3. Which sources count

In this order. Stop at the first that answers:

1. **Official docs or the project's own repo** (README, `docs/`, the source
   file, the JSON schema). This is the only source you may quote as definitive.
2. **Release notes / CHANGELOG / migration guide**, for "when did this change".
3. **A dated issue, PR or Stack Overflow answer**, for a specific error. Check
   the date and the version; an answer from three majors ago is a trap.
4. **Blog posts and tutorials**: orientation only. Never the sole source for a
   signature, a flag or a default.

Two rules that matter more than the ranking:

- **Never cite a page you did not read.** A search excerpt is a hint; if the
  fact goes into code, `web.sh read` the URL and take the exact text.
- **Version-match.** Check what is installed here first (`npm ls pkg`,
  `pip show pkg`, `go list -m all | grep pkg`) and read the docs for *that*
  version. Docs for the latest release are the most common source of
  confidently wrong code.

## 4. Budget

- **One search plus one read.** If that answers, stop and write the code.
- **Two rounds maximum**, then either the answer is good enough or it is
  unverified — say which and move on.
- Never read a whole documentation site. Search for the section, read it,
  leave.
- If both engines fail (`web.sh search` prints a failure), that is an answer
  too: report that you could not verify it. Do not substitute a guess.

## 5. There is nobody to delegate to — so stop instead

There used to be an `analyze` subagent to hand a long question to. It is gone
(2026-09-07): with `-np 1` on llama.cpp it queued behind the caller instead of
running in parallel, so it never bought speed, and its `task` tool cost ~760
tok/turn of schema on every turn of every task to buy context isolation that
`web.sh`'s own truncation (4000 chars a search, 6000 a page) already provides.

So the budget in §4 is not a suggestion you can escalate past — it is the whole
mechanism. When two rounds do not resolve it:

> FACT: UNKNOWN — could not verify from this machine.
> SOURCE: <what you actually ran or fetched>
> CAVEAT: <what would be needed: credentials, a specific URL, a version>

Returning UNKNOWN quickly is a **success**. It costs one cheap turn and keeps a
fabricated fact out of the code. Guessing to look helpful is the worst outcome
available here.

## 6. Bring the answer back

Copy the exact text (a signature, a key, a flag), not your paraphrase of it,
and record it with its source so the next turn does not repeat the search:

```markdown
# VERIFIED FACTS

- SKILL.md accepts only name, description, license, compatibility, metadata —
  source: https://opencode.ai/docs/skills/ (read 2026-09-01)
```

Then state the fact with its source in your answer. A fact whose source you
cannot name is a guess, and it belongs in the `unverified` wording from the
`stop-and-verify` skill.
