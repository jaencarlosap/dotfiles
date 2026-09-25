# opencode-mcp

- MCP tool permissions: global rules decide which tools enter the schema; an agent-level deny removes a tool from that agent, an agent-level allow does NOT add one the global config denies — source: proxy capture 2026-09-14
- `permission: deny` on an MCP tool name really removes it from the request (verified with a proxy in front of llama.cpp); a tool whose JSON Schema llama.cpp cannot compile breaks every request until denied — source: 2026-09-14
- Every declared MCP server injects 3 plumbing tools (list_mcp_resources, ...) into every agent, ~197 tok/turn — source: opencode-config README
- All MCP servers go through mcp.sh (mcporter) with `mcp: {}` in opencode.jsonc; adding one = entry in mcporter/mcporter.json + policy.json + `mcporter auth <name>` — source: README 2026-09-18
- mcporter reads a JSON body from stdin when it is not a TTY: every call from scripts uses stdin=/dev/null — source: bin/_mcp.py
- mcporter stores a token under sha256(name+url)[:16] in $XDG_DATA_HOME/mcporter or ~/.mcporter; authenticating by URL instead of by name hides it, and changing a server's url retires it. Diagnose with mcp.sh doctor — source: mcporter dist/oauth-vault.js 2026-09-22
- mcp.sh no debe depender de flags de mcporter: --no-oauth no existe en versiones < 0.13 y rompia cada call ('Unknown flag'). Se detecta la capacidad por version, se fija MCPORTER_OAUTH_NO_BROWSER=1 y hay preflight local del vault antes de invocar — source: reporte del segundo PC 2026-09-23
- The shape of an MCP tool does not require a session: mcporter/schemas/<server>.json is a committed snapshot (mcp.sh snapshot <server>) that mcp.sh uses for tools/describe/validation when there is no session or no network; only  needs auth — source: 2026-09-24
- The shape of an MCP tool does not require a session: mcporter/schemas/<server>.json is a committed snapshot (mcp.sh snapshot) used by mcp.sh for tools/describe/validation when there is no session or network; only calling needs auth — source: 2026-09-24
- Memory search is hybrid: SQLite FTS5 + embeddings from the local qwen-embed model (llama-swap), fused with RRF; measured 92% vs 79% with the old synonym table, which was deleted — source: test/memory-retrieval.py 2026-09-25
