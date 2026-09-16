#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# notion.sh — Notion desde `bash`, encima del CLI oficial `ntn`.
#
# Por que existe: el MCP de Notion costaba 4370 tok/turno solo para LEER
# (search + fetch + list-*), y escribir obligaba a un subagente (781 tok/turno
# de `task` + un verificador porque el modelo invento una URL). `ntn` (CLI
# oficial, beta) hace lo mismo con OAuth de usuario —el mismo alcance que el
# MCP: lo que tu ves, ve el agente— y por bash cuesta 0 tokens de esquema.
#
# Igual que web.sh: la salida entra en el contexto del modelo y va TRUNCADA.
# La URL/id de una pagina creada sale del CLI, no la escribe el modelo: si
# `ntn` falla, esto falla con su error, y no hay nada que inventar.
#
# Requiere: `ntn` en el PATH (make clis) y `ntn login` hecho una vez.
# OJO: `ntn` lee un body por stdin si stdin no es TTY y se queda esperando —
# desde un agente SIEMPRE lo es. Por eso cada llamada lleva `< /dev/null`.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

MAX_CHARS=${NOTION_MAX_CHARS:-6000}
RESULTS=${NOTION_RESULTS:-8}

usage() {
  cat <<'EOF'
notion.sh — your Notion, four commands. Run with bash.

  notion.sh search <words>                  pages/databases matching, with ids and URLs
  notion.sh get <id|url>                    a page as Markdown (truncated; NOTION_MAX_CHARS)
  notion.sh create [--parent <id|url>] < file.md     new page; first `# Heading` is the title
  notion.sh append <id|url> < file.md       add Markdown at the END of an existing page
  notion.sh replace <id|url> < file.md      replace the whole page content (asks nothing: be sure)

Without --parent, `create` makes a private page at the workspace root.
Content comes from stdin (a file or a heredoc), never from an argument: pass
the full text, verbatim. Output ends with the page id and URL — copy those,
never type a URL yourself.
EOF
}

need() { command -v ntn >/dev/null 2>&1 || { echo "ntn (Notion CLI) is not installed. Run: make clis   (opencode-config)" >&2; exit 1; }; }

# Acepta id con o sin guiones, o una URL de Notion; devuelve el id de 32 hex.
page_id() {
  local s="$1" id
  id=$(printf '%s' "$s" | grep -oE '[0-9a-fA-F]{32}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' | tail -1 | tr -d '-' | tr 'A-F' 'a-f')
  [ -n "$id" ] || { echo "not a Notion page id or URL: $s" >&2; exit 1; }
  printf '%s' "$id"
}

truncate_out() {
  python3 -c '
import sys
lim=int(sys.argv[1]); t=sys.stdin.read()
sys.stdout.write(t[:lim])
if len(t)>lim: print(f"\n  [...truncated: {len(t)-lim} chars more. Raise NOTION_MAX_CHARS if you need the rest.]")' "$MAX_CHARS"
}

cmd_search() {
  [ $# -ge 1 ] || { usage; exit 1; }
  ntn api v1/search query="$*" page_size:="$RESULTS" < /dev/null 2>&1 | python3 -c '
import sys,json
raw=sys.stdin.read()
try: d=json.loads(raw)
except Exception: print(raw.strip()[:800]); sys.exit(1)
res=d.get("results",[])
if not res: print("no results in Notion for:", " ".join(sys.argv[1:])); sys.exit(0)
for r in res:
    props=r.get("properties") or {}
    t=(props.get("title") or props.get("Name") or {}).get("title") or r.get("title") or []
    title="".join(x.get("plain_text","") for x in t) or "(untitled)"
    kind=r.get("object",""); pid=r.get("id","").replace("-",""); url=r.get("url","")
    print(f"- [{kind}] {title}")
    print(f"    id: {pid}   {url}")
if d.get("has_more"): print("  (more results; add words to narrow)")' "$@"
}

cmd_get() {
  [ $# -ge 1 ] || { usage; exit 1; }
  local id; id=$(page_id "$1")
  ntn pages get "$id" < /dev/null 2>&1 | truncate_out
}

report_page() {
  # ntn pages create imprime el id; se completa con la URL real de la API.
  local id="$1"
  local url
  url=$(ntn api "v1/pages/$id" < /dev/null 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin).get("url",""))' 2>/dev/null || true)
  echo "page id: $id"
  [ -n "$url" ] && echo "url: $url"
}

cmd_create() {
  local parent=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --parent) parent="page:$(page_id "$2")"; shift 2 ;;
      *) echo "unknown option: $1 (content comes from stdin)" >&2; usage; exit 1 ;;
    esac
  done
  [ -t 0 ] && { echo "no content on stdin. Use:  notion.sh create < file.md" >&2; exit 1; }
  local content; content=$(cat)
  [ -n "$(printf '%s' "$content" | tr -d '[:space:]')" ] || { echo "empty content: nothing created" >&2; exit 1; }
  local id
  if [ -n "$parent" ]; then id=$(ntn pages create --parent "$parent" --content "$content" < /dev/null 2>&1)
  else id=$(ntn pages create --content "$content" < /dev/null 2>&1); fi
  id=$(printf '%s' "$id" | tail -1 | tr -d '-')
  case "$id" in *[!0-9a-f]*|"") echo "ntn pages create failed: $id" >&2; exit 1 ;; esac
  echo "created"; report_page "$id"
}

cmd_replace() {
  [ $# -ge 1 ] || { usage; exit 1; }
  local id; id=$(page_id "$1")
  [ -t 0 ] && { echo "no content on stdin. Use:  notion.sh replace <id> < file.md" >&2; exit 1; }
  local content; content=$(cat)
  ntn pages edit "$id" --content "$content" < /dev/null >/dev/null
  echo "replaced"; report_page "$id"
}

cmd_append() {
  [ $# -ge 1 ] || { usage; exit 1; }
  local id; id=$(page_id "$1")
  [ -t 0 ] && { echo "no content on stdin. Use:  notion.sh append <id> < file.md" >&2; exit 1; }
  local add; add=$(cat)
  # get devuelve frontmatter (--- title ---) + cuerpo; el frontmatter no se reenvia.
  local cur
  cur=$(ntn pages get "$id" < /dev/null | python3 -c '
import sys,re
t=sys.stdin.read()
print(re.sub(r"\A---\n.*?\n---\n\n?","",t,count=1,flags=re.S),end="")')
  ntn pages edit "$id" --content "$(printf '%s\n\n%s\n' "$cur" "$add")" < /dev/null >/dev/null
  echo "appended"; report_page "$id"
}

[ $# -lt 1 ] && { usage; exit 1; }
need
what="$1"; shift || true
case "$what" in
  search)  cmd_search "$@" ;;
  get)     cmd_get "$@" ;;
  create)  cmd_create "$@" ;;
  append)  cmd_append "$@" ;;
  replace) cmd_replace "$@" ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
