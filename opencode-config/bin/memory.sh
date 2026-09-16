#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# memory.sh — memoria del agente en ficheros de texto, desde `bash`.
#
# Dos ambitos, dos formas de leerse:
#
#   GLOBAL  ~/.config/opencode/memory/   (symlink al repo: VERSIONADO, lo curas
#           tu con git)
#             preferences.md   reglas de como trabajar. Van SIEMPRE en contexto
#                              (estan en `instructions` de opencode.jsonc), por
#                              eso el tope de lineas es duro.
#             topics/<tema>.md hechos sobre una herramienta/servicio que no son
#                              de un repo concreto. Bajo demanda: `search`/`show`.
#
#   REPO    .agent/memory.md   (gitignored) hechos de ESTE repo que sobreviven a
#           la tarea. `promote` los saca de los VERIFIED FACTS del progress.md
#           al archivarlo. ground-truth los inyecta en cada turno.
#
# Igual que web.sh/docs.sh: se llama desde bash, 0 tokens de esquema hasta que
# se usa. Toda escritura es append con dedup por linea; nunca reescribe.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

MEM="${OPENCODE_MEMORY_DIR:-$HOME/.config/opencode/memory}"
PREFS="$MEM/preferences.md"
TOPICS="$MEM/topics"
REPO_MEM=".agent/memory.md"
PROGRESS=".agent/progress.md"

PREFS_MAX=${MEMORY_PREFS_MAX:-20}     # lineas de regla (sin cabecera)
REPO_MAX=${MEMORY_REPO_MAX:-30}
SEARCH_MAX=${MEMORY_SEARCH_MAX:-20}   # lineas de salida de `search`

usage() {
  cat <<'EOF'
memory.sh — what you learned, kept in text files. Run it with bash.

  memory.sh save "<fact> — source: <cmd or file:line>"      this repo (.agent/memory.md)
  memory.sh save --topic <name> "<fact> — source: ..."       global topic (memory/topics/<name>.md)
  memory.sh save --pref "<rule>"                             global preference (always in context)
  memory.sh promote [--from-done]                            VERIFIED FACTS of .agent/progress.md
                                                             (and of .agent/done-*.md) -> .agent/memory.md
  memory.sh search <term> [term...]                          grep all memory, best matches first
  memory.sh show [pref|repo|topics|<topic>]                  print one store (default: everything)
  memory.sh index                                            one line per topic (what exists)

Rules: write in English, identifiers verbatim, one fact per line, with its
source. A preference is something the user stated as a RULE (always / never /
from now on / prefiero), not a one-off instruction.
EOF
}

# append_unique <file> <header> <line> <max>   -> 0 saved, 2 duplicate, 3 full
append_unique() {
  local f="$1" header="$2" line="$3" max="$4"
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || printf '%s\n\n' "$header" > "$f"
  line="- ${line#- }"
  if grep -qxF -- "$line" "$f"; then echo "  (already there) $line"; return 2; fi
  local n; n=$(grep -c '^- ' "$f" || true)
  if [ "$n" -ge "$max" ]; then
    echo "  FULL: $f has $n entries (max $max). Merge or drop one first (memory.sh show), then save again." >&2
    return 3
  fi
  printf '%s\n' "$line" >> "$f"
  echo "  saved -> $f"
}

cmd_save() {
  case "${1:-}" in
    --pref)
      shift; [ $# -ge 1 ] || { usage; exit 1; }
      append_unique "$PREFS" "# Preferences (always in context — keep under $PREFS_MAX lines, one rule per line, English)" "$*" "$PREFS_MAX" ;;
    --topic)
      shift; local topic="${1:-}"; shift || true
      [ -n "$topic" ] && [ $# -ge 1 ] || { usage; exit 1; }
      case "$topic" in *[!a-zA-Z0-9._-]*) echo "topic name: letters, digits, . _ - only" >&2; exit 1 ;; esac
      append_unique "$TOPICS/$topic.md" "# $topic" "$*" 200 ;;
    "") usage; exit 1 ;;
    *)
      mkdir -p .agent
      grep -qxF '.agent/' .gitignore 2>/dev/null || echo '.agent/' >> .gitignore
      append_unique "$REPO_MEM" "# Repo memory (facts that outlive a task — one per line, with source)" "$*" "$REPO_MAX" ;;
  esac
}

# Lineas "- ..." de la seccion VERIFIED FACTS de un fichero de progreso.
facts_of() {
  awk '/^#+[ \t]*VERIFIED FACTS[ \t]*$/{p=1;next} /^#/{p=0} p && /^- /' "$1" 2>/dev/null || true
}

cmd_promote() {
  local files=() saved=0 dup=0 full=0
  [ -f "$PROGRESS" ] && files+=("$PROGRESS")
  if [ "${1:-}" = "--from-done" ]; then
    for f in .agent/done-*.md; do [ -f "$f" ] && files+=("$f"); done
  fi
  [ ${#files[@]} -gt 0 ] || { echo "nothing to promote: no $PROGRESS" >&2; exit 1; }
  mkdir -p .agent
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    set +e; append_unique "$REPO_MEM" "# Repo memory (facts that outlive a task — one per line, with source)" "$line" "$REPO_MAX" >/dev/null 2>&1; rc=$?; set -e
    case $rc in 0) saved=$((saved+1));; 2) dup=$((dup+1));; 3) full=$((full+1));; esac
  done < <(for f in "${files[@]}"; do facts_of "$f"; done)
  local extra=""; [ "$full" -gt 0 ] && extra=", $full skipped: file full"
  echo "  promoted $saved fact(s) to $REPO_MEM ($dup already there$extra)"
  [ "$full" -gt 0 ] && echo "  $REPO_MEM is at its limit ($REPO_MAX). Merge or drop stale lines (memory.sh show repo)." >&2
  return 0
}

cmd_search() {
  [ $# -ge 1 ] || { usage; exit 1; }
  local files=()
  [ -f "$PREFS" ] && files+=("$PREFS")
  for f in "$TOPICS"/*.md; do [ -f "$f" ] && files+=("$f"); done
  [ -f "$REPO_MEM" ] && files+=("$REPO_MEM")
  [ -f "$PROGRESS" ] && files+=("$PROGRESS")
  [ ${#files[@]} -gt 0 ] || { echo "no memory yet"; return 0; }
  python3 - "$SEARCH_MAX" "$MEM" "$@" -- "${files[@]}" <<'PY'
import sys,re,os
args=sys.argv[1:]; mx=int(args[0]); mem=args[1]; sep=args.index("--")
terms=[t.lower() for t in args[2:sep]]; files=args[sep+1:]
hits=[]
for f in files:
    try: lines=open(f,encoding="utf8",errors="replace").read().splitlines()
    except Exception: continue
    for i,l in enumerate(lines,1):
        if not l.strip() or l.startswith("#"): continue
        low=l.lower(); n=sum(1 for t in terms if t in low)
        if n: hits.append((-n,f,i,l.strip()))
hits.sort()
if not hits:
    print("no match in memory for:", " ".join(terms)); sys.exit(0)
for n,f,i,l in hits[:mx]:
    short=f.replace(mem+"/","memory/") if f.startswith(mem) else f
    print(f"{short}:{i}: {l}")
if len(hits)>mx: print(f"  … {len(hits)-mx} more; add terms to narrow")
PY
}

cmd_show() {
  local what="${1:-all}"
  case "$what" in
    pref|prefs)  cat "$PREFS" 2>/dev/null || echo "no preferences yet" ;;
    repo)        cat "$REPO_MEM" 2>/dev/null || echo "no repo memory yet ($REPO_MEM)" ;;
    topics)      cmd_index ;;
    all)
      echo "## $PREFS"; cat "$PREFS" 2>/dev/null || echo "(none)"
      echo; echo "## topics"; cmd_index
      echo; echo "## $REPO_MEM"; cat "$REPO_MEM" 2>/dev/null || echo "(none)" ;;
    *)
      [ -f "$TOPICS/$what.md" ] && cat "$TOPICS/$what.md" || { echo "no topic '$what'. Existing:" >&2; cmd_index >&2; exit 1; } ;;
  esac
}

cmd_index() {
  local any=0
  for f in "$TOPICS"/*.md; do
    [ -f "$f" ] || continue; any=1
    printf '  %s (%s facts)\n' "$(basename "$f" .md)" "$(grep -c '^- ' "$f" || true)"
  done
  [ $any -eq 1 ] || echo "  (no topics yet)"
}

[ $# -lt 1 ] && { usage; exit 1; }
what="$1"; shift || true
case "$what" in
  save)    cmd_save "$@" ;;
  promote) cmd_promote "$@" ;;
  search)  cmd_search "$@" ;;
  show)    cmd_show "$@" ;;
  index)   cmd_index ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
