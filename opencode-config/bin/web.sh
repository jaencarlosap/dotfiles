#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# web.sh — buscar en la web y leer una pagina, desde `bash`.
#
# Por que existe: el escalon final del knowledge-protocol ("mira la web") no
# tenia con que ejecutarse. El MCP de duckduckgo devolvia `202 Ratelimit` en
# cada llamada, y `webfetch` solo sirve cuando YA sabes la URL — que es justo
# lo que no sabes cuando no conoces algo.
#
# Que se usa aqui, y por que:
#
#   search -> https://mcp.exa.ai/mcp  (el MISMO backend que usa la herramienta
#             `websearch` de opencode; verificado sin clave desde esta maquina:
#             devuelve titulo + URL + extractos del contenido).
#             Fallback: html.duckduckgo.com, que hoy SI responde 200 desde el
#             Mac (el que fallaba era el contenedor del MCP), pero solo da
#             titulo + URL, sin extracto.
#
#   read   -> curl + limpieza de HTML. Existe porque el agente `auto` NO tiene
#             `webfetch` (se le quito para no pagar su esquema en cada turno):
#             con esto puede leer una pagina sin esa herramienta.
#
# Igual que docs.sh: se llama desde `bash`, asi que cuesta 0 tokens de esquema
# hasta que se usa, a diferencia de un MCP (que mete su esquema en el prompt de
# CADA turno).
#
# La salida entra en el contexto del modelo: va TRUNCADA a proposito.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

MAX_CHARS_SEARCH=${WEB_MAX_CHARS:-4000}   # extractos de busqueda
MAX_CHARS_READ=${WEB_READ_CHARS:-6000}    # texto de una pagina

usage() {
  cat <<'EOF'
web.sh — la web, en dos comandos.

  web.sh search <consulta>     busca: titulo + URL + extracto de cada resultado
  web.sh read   <url>          descarga una pagina y la deja en texto plano

Ejemplos:
  web.sh search "opencode SKILL.md frontmatter fields"
  web.sh read https://opencode.ai/docs/skills/

Variables: WEB_ENGINE=ddg (fuerza el buscador de respaldo)
           WEB_MAX_CHARS (extracto de busqueda, def. 4000)
           WEB_READ_CHARS (texto de pagina, def. 6000)
           WEB_RESULTS     (numero de resultados, def. 5)

Antes de venir aqui: para un paquete usa `docs.sh npm|py|rs|go|mdn|wiki`, y
para algo YA instalado mira el disco (grep en el repo, `go doc`, `--help`).
EOF
}

# Exa habla MCP sobre HTTP y contesta en SSE (`data: {...}`). Se manda el
# handshake implicito: una sola llamada tools/call basta.
search_exa() {
  local q="$1" n="$2"
  local payload
  payload=$(python3 -c '
import json,sys
q,n=sys.argv[1],int(sys.argv[2])
print(json.dumps({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{
  "name":"web_search_exa",
  "arguments":{"query":q,"type":"auto","numResults":n,"livecrawl":"fallback",
               "contextMaxCharacters":'"$MAX_CHARS_SEARCH"'}}}))' "$q" "$n")

  curl -s -m 40 -X POST "https://mcp.exa.ai/mcp" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "User-Agent: opencode-web.sh/1.0" \
    -d "$payload" \
  | python3 -c '
import sys,json
raw=sys.stdin.read()
txt=""
for line in raw.splitlines():
    if not line.startswith("data: "): continue
    try: obj=json.loads(line[6:])
    except Exception: continue
    for c in (obj.get("result") or {}).get("content",[]):
        if c.get("text"): txt+=c["text"]
if not txt.strip(): sys.exit(1)
print(txt.strip()[:'"$MAX_CHARS_SEARCH"'])'
}

# Fallback sin extractos: solo titulo + URL. Sirve para conseguir la URL y
# luego pasarsela a `web.sh read`.
search_ddg() {
  local q="$1" n="$2"
  curl -s -m 25 -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" \
    --data-urlencode "q=$q" "https://html.duckduckgo.com/html/" \
  | python3 -c '
import sys,re,html,urllib.parse
page=sys.stdin.read()
n=int(sys.argv[1]); out=[]
for m in re.finditer(r"<a[^>]*class=\"result__a\"[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>",page,re.S):
    url,title=m.group(1),re.sub(r"<[^>]+>","",m.group(2))
    if url.startswith("//duckduckgo.com/l/"):
        qs=urllib.parse.parse_qs(urllib.parse.urlparse("https:"+url).query)
        url=qs.get("uddg",[url])[0]
    out.append(f"- {html.unescape(title).strip()}\n  {html.unescape(url)}")
    if len(out)>=n: break
if not out: sys.exit(1)
print("\n".join(out))' "$n"
}

cmd_search() {
  local q="$*" n="${WEB_RESULTS:-5}"
  [ -z "$q" ] && { usage; exit 1; }
  # WEB_ENGINE=ddg fuerza el fallback (sirve para comprobar que sigue vivo).
  if [ "${WEB_ENGINE:-}" != "ddg" ] && search_exa "$q" "$n"; then
    echo "  (fuente: exa)"
    return 0
  fi
  echo "  (exa no respondio; caigo a duckduckgo — sin extractos)" >&2
  if search_ddg "$q" "$n"; then
    echo "  (fuente: duckduckgo — solo titulos, usa 'web.sh read <url>' para el contenido)"
    return 0
  fi
  echo "SIN RESULTADOS: los dos buscadores fallaron. NO te inventes la respuesta:" >&2
  echo "di que no pudiste verificarlo y sigue con lo que si puedas comprobar." >&2
  return 1
}

cmd_read() {
  local url="$1"
  [ -z "$url" ] && { usage; exit 1; }
  case "$url" in http://*|https://*) ;; *) echo "URL invalida: $url" >&2; exit 1 ;; esac

  # Se guarda el CODIGO HTTP aparte. Sin esto una 404 se cuela como si fuera
  # contenido ("404: Not Found" son bytes validos) y el modelo sigue como si
  # hubiera leido la pagina. Visto en un run real: invento la URL de unas docs,
  # recibio una 404 y continuo.
  local body status
  body=$(mktemp)
  status=$(curl -sL -m 30 -o "$body" -w '%{http_code}' \
    -A "Mozilla/5.0 (compatible; opencode-web.sh/1.0)" "$url" || echo 000)
  if [ "$status" != "200" ]; then
    rm -f "$body"
    echo "HTTP $status en $url — esa pagina NO existe o no se pudo leer." >&2
    echo "No adivines otra URL: buscala con  web.sh search \"<terminos exactos>\"" >&2
    exit 1
  fi

  cat "$body" \
  | python3 -c '
import sys,re,html
raw=sys.stdin.read()
raw=re.sub(r"(?is)<(script|style|noscript|svg|head|nav|header|footer|aside)[^>]*>.*?</\1>"," ",raw)
raw=re.sub(r"(?is)<!--.*?-->"," ",raw)
# Si la pagina marca su contenido, quedate SOLO con el: en un sitio de docs el
# menu lateral es mas largo que el articulo y se comeria el limite de chars.
for tag in ("main","article"):
    m=re.search(r"(?is)<%s[^>]*>(.*?)</%s>"%(tag,tag),raw)
    if m and len(m.group(1))>500: raw=m.group(1); break
raw=re.sub(r"(?i)</(p|div|li|tr|h[1-6]|pre|section|article)>","\n",raw)
raw=re.sub(r"(?i)<br\s*/?>","\n",raw)
txt=html.unescape(re.sub(r"<[^>]+>"," ",raw))
txt=re.sub(r"[ \t\r\f\v]+"," ",txt)
txt="\n".join(l.strip() for l in txt.split("\n") if l.strip())
txt=re.sub(r"\n{3,}","\n\n",txt)
if not txt.strip(): sys.exit(1)
limit='"$MAX_CHARS_READ"'
print(txt[:int(limit)])
if len(txt)>int(limit):
    print(f"\n  [...truncado: {len(txt)-int(limit)} chars mas. Si necesitas otra parte, "
          f"vuelve a llamar con WEB_READ_CHARS mas alto o busca la seccion concreta.]")' \
  || { rm -f "$body"; echo "No pude leer $url (o no devolvio texto). No inventes su contenido." >&2; exit 1; }
  rm -f "$body"
}

[ $# -lt 1 ] && { usage; exit 1; }
what="$1"; shift || true

case "$what" in
  search) cmd_search "$@" ;;
  read)   cmd_read "${1:-}" ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
