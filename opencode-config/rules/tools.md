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
notion.sh search|get|create|append    # the user's Notion; content via stdin, the URL comes back
acli jira workitem view|search|create # Jira (the `jira-ticket` skill has the create recipe)
acli confluence ...                   # Confluence
gh pr view|diff|checks|list           # GitHub, read side; also gh issue view|list, gh run list|view
```

Rules that apply to all of them:

- **The command's output is the fact.** The page id or URL you report is the
  one `notion.sh` printed; the ticket key is the one `acli` returned; the PR
  number is what `gh` said. Never type one yourself, never reconstruct one.
- **If a command fails, report its error line.** Do not retry with a guessed
  URL, id or flag. `unauthorized` means the user has to log in once
  (`acli jira auth login --web`, `ntn login`, `gh auth login`): say exactly that.
- **Writes take the full text.** To save something to Notion, write it to a
  file or a heredoc and pipe it to `notion.sh create` / `append` — never a
  summary of it.
- **Publishing and deleting ask first** (`gh pr create` only via `/pr`,
  `gh pr merge`, `git push`, `rm -rf`): the permission prompt is the
  confirmation, do not ask twice in prose.
- Any MCP tool that does appear in your tool list (`<server>_<tool>`) is
  connected right now: call it, never say none is configured.
