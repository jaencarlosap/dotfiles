# opencode-mcp

- MCP tool permissions: global rules decide which tools enter the schema; an agent-level deny removes a tool from that agent, an agent-level allow does NOT add one the global config denies — source: proxy capture 2026-09-14
- `permission: deny` on an MCP tool name really removes it from the request (verified with a proxy in front of llama.cpp); a tool whose JSON Schema llama.cpp cannot compile breaks every request until denied — source: 2026-09-14
- Every declared MCP server injects 3 plumbing tools (list_mcp_resources, ...) into every agent, ~197 tok/turn — source: opencode-config README
