# Notion

- Notion is used through `notion.sh` (bin/, wraps the official `ntn` CLI): search | get | create | append | replace; content via stdin, the URL comes back from the command — source: opencode-config bin/notion.sh
- `ntn login` is user OAuth: the agent sees what the user sees, no per-page sharing — source: developers.notion.com/cli
- `ntn` blocks waiting for a stdin body whenever stdin is not a TTY (always, from an agent); every call needs `< /dev/null` — source: hang reproduced 2026-09-15
- The Notion MCP was tried and removed: 43 tools (~61k tok of schema), 4370 tok/turn even for the read-only allowlist, and `notion-create-comment` has a schema llama.cpp cannot compile — source: opencode-config README 2026-09-14/15
