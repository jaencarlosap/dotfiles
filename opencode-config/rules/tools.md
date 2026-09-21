# Tools on your PATH

Beyond the native tools, you have commands on your PATH, run through plain
`bash`. Each costs nothing until you run it; that is why there is no webfetch
tool, no MCP server and no subagent here. Run them — never open them with the
read tool. Their output is truncated on purpose: it lands in your context.
The list is in lookup order — cheapest and closest first — then the commands
that act on the user's systems. Keep new entries in that order.

```bash
memory.sh search "<terms>"            # what you already learned, this repo or any — check first
memory.sh save ... | promote          # keep a fact / a preference (see the agent prompt for when)
docs.sh npm|py|rs|go|mdn|wiki <pkg>   # package registries: exists? current version? docs?
web.sh search "<exact identifiers>"   # web: titles + URLs + excerpts (Exa, falls back to DuckDuckGo)
web.sh read <url>                     # that page as plain text
mcp.sh list                           # every external service you can reach right now (documents, tickets, data...)
mcp.sh tools <server> <word>          # what a server can do, filtered by a word (search, page, quote...); [write] = changes things
mcp.sh describe <server>.<tool>       # one tool in full, when the signature is not enough
mcp.sh call <server>.<tool> k=v ...   # read; JSON values with k:='{...}', files with k=@path
mcp.sh call --write <server>.<tool> … # create/update/send — the user confirms the exact command
gh pr view|diff|checks|list           # GitHub, read side; also gh issue view|list, gh run list|view
```

Rules that apply to all of them:

- **The command's output is the fact.** The page id or URL you report is the
  one `mcp.sh call` printed; the ticket key is the one the server returned; the
  PR number is what `gh` said. Never type one yourself, never reconstruct one.
- **If a command fails, report its error line.** Do not retry with a guessed
  URL, id or flag. `unauthorized` means the user has to log in once
  (`mcporter auth <server>`, `gh auth login`): say exactly that.
- **Writes take the full text.** To save something (a page, a ticket, a
  note) put the whole content in the call — from a file with `k=@path` when
  it is long — never a summary of it.
- **MCP servers are discovered, not remembered.** `mcp.sh tools <server> <word>`
  costs ~50 tokens per matching tool — always pass a word (the whole list of a
  big server is ~1k tokens). Do it once per session per server, then call. A
  tool `tools` does not list cannot be called — do not guess names. Two hops
  the first time, one after.
- **Publishing and deleting ask first** (`gh pr create` only via `/pr`,
  `gh pr merge`, `git push`, `rm -rf`): the permission prompt is the
  confirmation, do not ask twice in prose.
- Any MCP tool that does appear in your tool list (`<server>_<tool>`) is
  connected right now: call it, never say none is configured.
