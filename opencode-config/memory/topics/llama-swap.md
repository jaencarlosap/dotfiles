# llama-swap (model server on pcgamer:1234, llama.cpp behind it)

- Backend is llama-swap + llama.cpp, NOT LM Studio; the provider key in opencode.jsonc is `local` (was `lmstudio`, renamed 2026-09-15) — source: curl http://pcgamer:1234/v1/models | grep owned_by
- Model ids are llama-swap's own names (qwen-35b, qwen-9b, gpt-oss-20b), not HuggingFace paths; check with `make models` in opencode-config — source: /v1/models
- An unknown model id is NOT silent: HTTP 404 "no router for requested model" — source: llama-swap response
- The server caps reasoning with `--reasoning-budget 700`, so `reasoningEffort` in opencode has no measurable effect — source: curl pcgamer:1234/running
- A tool whose JSON Schema llama.cpp cannot turn into a grammar breaks EVERY request: "Failed to initialize samplers: failed to parse grammar" (seen with notion-create-comment) — source: opencode-config README 2026-09-14
- Decode speed measured 60.3 tok/s on UD-IQ3_XXS with --n-cpu-moe 16 — source: make bench
