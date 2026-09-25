# opencode

- opencode run --agent <subagent> silently falls back to the default primary agent; test subagents through task from a primary agent — source: proxy capture 2026-09-14
- A small model can answer CREATED/DONE without calling any tool (a subagent once invented a Notion URL); prefer commands whose output IS the proof (mcp.sh prints the id/URL the server returned) over trusting a report — source: opencode.db part table 2026-09-14
- Never put temperature/top_p in an agent's frontmatter: it is sent to every model and GPT reasoning models reject top_p; set them per provider in plugin/sampling.ts (chat.params) — source: opencode-config README 2026-09-15
- Agent-level permission rules run AFTER the global ones and the last match wins: a 'bash: allow' in an agent's frontmatter silently disabled every global bash 'ask' (sudo, git push, mcp.sh call --write) for that agent; keep agent permissions to what differs — source: opencode.log 'evaluated permission' 2026-09-21
- opencode auto-discovers ~/.claude/skills (claude.ai synced ones) and there is no opt-out (issue #12604); their descriptions cost tokens in EVERY turn — deny them in permission.skill, which removes them from the prompt too (verified: -2048 tok/turn) — source: proxy capture 2026-09-22
- external_directory '*: ask' made the agent ask permission to use its own tools (memory.sh, mcp.sh read ~/.config/opencode): allowlist the setup's own paths and keep ask for the rest — source: opencode.log 2026-09-25
