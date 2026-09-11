#!/usr/bin/env bash
# Corre las 4 tareas con UN modelo. $1 = id del modelo, $2 = etiqueta corta,
# $3 = agente (opcional; sin el, el default_agent de opencode.jsonc). Sirve para
# comparar `auto` contra el `build` de serie con el MISMO modelo y las mismas
# tareas — la unica forma honesta de saber si el prompt propio ayuda o estorba.
set -uo pipefail
SP="$(cd "$(dirname "$0")" && pwd)"
model="$1"; tag="$2"; agent="${3:-}"
source "$SP/prompts.sh"
for task in redtest newproj lookup ticket; do
  dir="$SP/$tag-$task"
  bash "$SP/setup.sh" "$task" "$dir"
  var="prompt_$task"; prompt="${!var}"
  start=$(date +%s)
  ( cd "$dir" && opencode run -m "$model" ${agent:+--agent "$agent"} "$prompt" > run.txt 2>&1 )
  end=$(date +%s)
  echo "$((end-start))" > "$dir/.seconds"
  echo "[$tag/$task] $((end-start))s"
done
echo "FIN $tag"
