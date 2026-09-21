# Notion

- Notion goes through mcp.sh (mcporter): `mcp.sh tools notion <word>` then `mcp.sh call notion.notion-search query=...` / `notion-fetch id=...`; writes need `--write` — source: opencode-config bin/mcp.sh
- The server exposes 45 tools (2026-09-18; 43 on 09-14): policy hides sessions/agents/skills/attachments/comments; create/update/move/duplicate are write — source: mcporter/policy.json
- No destination for a new page -> `creation_mode=draft` (private workspace-level page); never search for a destination the user did not name — source: notion-create-pages description
- The Notion MCP in opencode.jsonc was measured at 4370 tok/turn read-only and `notion-create-comment` breaks llama.cpp's grammar; never declare it natively — source: README 2026-09-14/15
- Pages inside a DATABASE need the data source's exact property names: fetch `collection://<id>` first; the title property is not always "Name" (Habit Tracker: "Notes"); checkboxes take "__YES__"/"__NO__", dates "date:<Prop>:start" — source: validation_error text 2026-09-21
- create-pages with parent {"database_id"|"data_source_id"} and update-page (update_properties, insert_content, content=@file) all work through mcp.sh; "expected object, received string" means k= was used instead of k:= (mcp.sh now coerces by schema) — source: verified 2026-09-21
- A model once reported the hosted Notion MCP as "broken, known bugs #82/#192/#215": those issues belong to the local open-source server and the errors were argument syntax; never accept that verdict without reproducing — source: 2026-09-21
