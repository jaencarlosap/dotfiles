---
description: Build + test the project and report pass/fail concisely
agent: auto
---

Verify that the project actually works. Do NOT edit code in this command —
only detect, run, and report.

1. Detect the project type by what exists in the repo root (check in order):
   - `go.mod`        → `go build ./...` then `go test ./...`
   - `package.json`  → read its `scripts`; run the `build` script if present,
                       then the `test` script if present (use the repo's
                       package manager: bun > pnpm > yarn > npm, whichever
                       lockfile exists).
   - `Cargo.toml`    → `cargo build` then `cargo test`
   - `pyproject.toml`/`setup.py` → `ruff check .` if available, then
                       `pytest -q` if tests exist.
   - none of these   → say so and stop.

2. Run the commands with a reasonable timeout. Do not stream full output into
   the chat — capture it and quote only the failing lines.

3. Report exactly one of:
   - `✅ VERIFY OK — <cmd(s)> passed` (one line), or
   - `❌ VERIFY FAILED` followed by the specific failing test / compile error
     with its `file:line`, nothing else.

If arguments were given, treat them as a narrower scope to verify: $ARGUMENTS
