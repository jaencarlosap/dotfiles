#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# docs.sh — consulta de paquetes/librerias SIN salir a un buscador.
#
# Por que existe: el escalon 5 del knowledge-protocol ("la web") estaba
# apoyado en el MCP de duckduckgo, y DuckDuckGo BLOQUEA a esta maquina
# (`202 Ratelimit`, y por navegador un captcha de patos). Comprobado: el MCP
# devuelve `Failed to retrieve results from DuckDuckGo` en cada llamada.
#
# Los registros de paquetes, en cambio, tienen APIs JSON estables, sin clave
# y sin captcha — y son justo lo que un modelo pequeño necesita consultar:
# "existe este paquete", "que version es la ultima", "donde estan sus docs".
#
# Se usa desde `bash`, asi que NO cuesta ni un token de esquema de herramienta
# hasta que se llama (a diferencia de un servidor MCP, que mete su esquema en
# el prompt de CADA turno).
#
# Salida deliberadamente CORTA: este output entra en el contexto del modelo.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

j() { python3 -c "import sys,json;d=json.load(sys.stdin);$1" 2>/dev/null || echo "  (sin datos)"; }

usage() {
  cat <<'EOF'
docs.sh — datos de un paquete, desde su registro oficial.

  docs.sh npm  <paquete>     npm: version, descripcion, repo, tipos
  docs.sh py   <paquete>     PyPI: version, resumen, python requerido, docs
  docs.sh rs   <crate>       crates.io: version, descripcion, docs.rs
  docs.sh go   <modulo>      proxy.golang.org: ultimas versiones publicadas
  docs.sh mdn  <consulta>    MDN: APIs web que coinciden
  docs.sh wiki <termino>     Wikipedia: resumen de una linea

Para una libreria YA INSTALADA usa antes lo local (mas fiable, es la version
real): grep en el repo, `go doc`, `python -c "help(pkg)"`, node_modules/**/*.d.ts
EOF
}

[ $# -lt 2 ] && { usage; exit 1; }
what="$1"; shift; q="$*"

case "$what" in
  npm)
    curl -s -m 20 "https://registry.npmjs.org/$q" | j "
v=d.get('dist-tags',{}).get('latest');i=d.get('versions',{}).get(v,{})
print(f\"  paquete : {d.get('name')}\");print(f\"  version : {v}\")
print(f\"  resumen : {(d.get('description') or '')[:160]}\")
print(f\"  repo    : {(d.get('repository') or {}).get('url','?')}\")
print(f\"  tipos   : {i.get('types') or i.get('typings') or 'no declara tipos'}\")
print(f\"  deps    : {', '.join(list((i.get('dependencies') or {}).keys())[:8]) or 'ninguna'}\")" ;;
  py)
    curl -s -m 20 "https://pypi.org/pypi/$q/json" | j "
i=d['info']
print(f\"  paquete : {i.get('name')}\");print(f\"  version : {i.get('version')}\")
print(f\"  resumen : {(i.get('summary') or '')[:160]}\")
print(f\"  python  : {i.get('requires_python') or '?'}\")
print(f\"  docs    : {i.get('docs_url') or i.get('project_url') or i.get('home_page') or '?'}\")
print(f\"  deps    : {', '.join((i.get('requires_dist') or [])[:6]) or 'ninguna'}\")" ;;
  rs)
    curl -s -m 20 -A "opencode-docs/1.0" "https://crates.io/api/v1/crates/$q" | j "
c=d['crate']
print(f\"  crate   : {c.get('name')}\");print(f\"  version : {c.get('max_stable_version') or c.get('max_version')}\")
print(f\"  resumen : {(c.get('description') or '')[:160]}\")
print(f\"  docs    : {c.get('documentation') or 'https://docs.rs/'+str(c.get('name'))}\")" ;;
  go)
    echo "  modulo  : $q"
    echo -n "  versiones (ultimas): "
    curl -s -m 20 "https://proxy.golang.org/$(echo "$q" | tr 'A-Z' 'a-z')/@v/list" | sort -V | tail -5 | tr '\n' ' '
    echo; echo "  docs    : https://pkg.go.dev/$q" ;;
  mdn)
    curl -s -m 20 "https://developer.mozilla.org/api/v1/search?q=$(echo "$q" | tr ' ' '+')" | j "
for r in d.get('documents',[])[:5]:
    print(f\"  - {r.get('title')}: https://developer.mozilla.org{r.get('mdn_url')}\")
    print(f\"      {(r.get('summary') or '')[:110]}\")" ;;
  wiki)
    curl -s -m 20 "https://en.wikipedia.org/api/rest_v1/page/summary/$(echo "$q" | tr ' ' '_')" | j "
print(f\"  {d.get('title')}: {(d.get('extract') or '')[:300]}\")" ;;
  *) usage; exit 1 ;;
esac
