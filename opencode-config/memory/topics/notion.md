# Notion

- Notion goes through mcp.sh (mcporter): `mcp.sh tools notion <word>` then `mcp.sh call notion.notion-search query=...` / `notion-fetch id=...`; writes need `--write` — source: opencode-config bin/mcp.sh
- The server exposes 45 tools (2026-09-18; 43 on 09-14): policy hides sessions/agents/skills/attachments/comments; create/update/move/duplicate are write — source: mcporter/policy.json
- No destination for a new page -> `creation_mode=draft` (private workspace-level page); never search for a destination the user did not name — source: notion-create-pages description
- The Notion MCP in opencode.jsonc was measured at 4370 tok/turn read-only and `notion-create-comment` breaks llama.cpp's grammar; never declare it natively — source: README 2026-09-14/15
