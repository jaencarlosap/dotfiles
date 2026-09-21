#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# mcp.sh — TODOS los servidores MCP, desde `bash`, encima de mcporter.
#
# Por que asi y no `mcp:` en opencode.jsonc: opencode 1.18 manda el esquema de
# CADA tool de CADA servidor en CADA turno (Notion solo lectura: 4370 tok/turno;
# los 43 tools: ~61k). Aqui el modelo descubre las tools cuando las necesita
# (`tools`, ~50 tok por firma) y las llama por bash: 0 tokens hasta que se usa.
# Es la "carga diferida" que los harnesses modernos hacen solos, hecha a mano.
#
# Una sola via de entrada: anadir un servidor = una entrada en
# mcporter/mcporter.json (symlink a ~/.mcporter/mcporter.json) + su politica en
# mcporter/policy.json + `mcporter auth <nombre>`. Sin tocar el agente.
#
# Politica (mcporter/policy.json), aplicada AQUI, no pedida al modelo:
#   deny  -> la tool no existe: `tools` no la lista, `call` la rechaza.
#   write -> solo con `mcp.sh call --write ...`; opencode.jsonc pone ese
#            comando en "ask", asi que el usuario ve la llamada entera antes.
#
# La logica vive en bin/_mcp.py (un fichero, testeable con un mcporter falso).
# La salida entra en el contexto del modelo: va truncada (MCP_MAX_CHARS).
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail
command -v python3 >/dev/null 2>&1 || { echo "python3 missing" >&2; exit 1; }
command -v "${MCP_MCPORTER_BIN:-mcporter}" >/dev/null 2>&1 || { echo "mcporter is not installed. Run: make clis   (opencode-config)" >&2; exit 1; }
exec python3 "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")/_mcp.py" "$@"
