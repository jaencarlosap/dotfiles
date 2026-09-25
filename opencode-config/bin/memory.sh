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
RECIPES="$MEM/recipes"
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
  memory.sh recipe <name> < steps.md                         a reusable procedure: the exact commands that worked
  memory.sh search <term> [term...]                          all memory: FTS5 + semantic (hybrid), best matches first
  memory.sh show [pref|repo|topics|recipes|<topic>]          print one store (default: everything)
  memory.sh index                                            one line per topic and recipe (what exists)
  memory.sh index --build|--embed|--stats                    search index: rebuild, add embeddings, show state
  memory.sh check                                            find stale entries: files/commands they name that no longer exist

Rules: write in English, identifiers verbatim, one fact per line, with its
source. A preference is something the user stated as a RULE (always / never /
from now on / prefiero), not a one-off instruction.

A RECIPE is what you would otherwise have to rediscover: the working sequence
of commands for a task (which tool, which parameters, in which order, what to
avoid). It costs nothing until someone searches for it — that is why a recipe
goes here and not into a skill, whose description is paid on every single turn.
EOF
}

# append_unique <file> <header> <line> <max>   -> 0 saved, 2 duplicate, 3 full
# Parecido, no identico: dos hechos que dicen lo mismo con otras palabras son
# la forma habitual de que la memoria se llene de ruido. Se avisa (no se
# bloquea): el modelo decide si es un matiz nuevo o si debe corregir el viejo.
similar_warning() {
  local f="$1" line="$2"
  [ -f "$f" ] || return 0
  python3 - "$f" "$line" <<'PY'
import sys,re,unicodedata
def fold(t):
    t=unicodedata.normalize("NFD",t.lower())
    return set(re.findall(r"[a-z0-9._/-]{4,}","".join(c for c in t if unicodedata.category(c)!="Mn")))
new=fold(sys.argv[2])
if not new: sys.exit(0)
for i,l in enumerate(open(sys.argv[1],encoding="utf8",errors="replace").read().splitlines(),1):
    if not l.startswith("- "): continue
    old=fold(l)
    if not old: continue
    # Cobertura del hecho NUEVO, no Jaccard: un hecho corto que repite lo que ya
    # dice uno largo es el caso tipico (y Jaccard lo dejaba pasar por longitud).
    j=len(new&old)/len(new)
    if j>=0.6:
        print(f"  ⚠️  parecido a la linea {i} ({int(j*100)}% de sus palabras ya estan ahi):")
        print(f"      {l[:150]}")
        print("      Si lo corrige, edita esa linea (o dilo al usuario); si es un matiz nuevo, sigue.")
        break
PY
}

append_unique() {
  local f="$1" header="$2" line="$3" max="$4"
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || printf '%s\n\n' "$header" > "$f"
  line="- ${line#- }"
  if grep -qxF -- "$line" "$f"; then echo "  (already there) $line"; return 2; fi
  similar_warning "$f" "$line"
  local n; n=$(grep -c '^- ' "$f" || true)
  if [ "$n" -ge "$max" ]; then
    echo "  FULL: $f has $n entries (max $max). Merge or drop one first (memory.sh show), then save again." >&2
    return 3
  fi
  printf '%s\n' "$line" >> "$f"
  echo "  saved -> $f"
  # El indice se actualiza en segundo plano: el hecho nuevo queda buscable por
  # significado sin que quien guarda espere los ~150 ms del embedding.
  local idx="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")/_memory_index.py"
  [ -f "$idx" ] && (OPENCODE_MEMORY_DIR="$MEM" python3 "$idx" embed >/dev/null 2>&1 &)
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

cmd_recipe() {
  local name="${1:-}"
  [ -n "$name" ] || { usage; exit 1; }
  case "$name" in *[!a-zA-Z0-9._-]*) echo "recipe name: letters, digits, . _ - only" >&2; exit 1 ;; esac
  [ -t 0 ] && { echo "no steps on stdin. Use:  memory.sh recipe <name> < steps.md   (or a heredoc)" >&2; exit 1; }
  local body; body=$(cat)
  [ -n "$(printf '%s' "$body" | tr -d '[:space:]')" ] || { echo "empty recipe: nothing saved" >&2; exit 1; }
  mkdir -p "$RECIPES"
  local f="$RECIPES/$name.md"
  if [ -f "$f" ]; then
    cp "$f" "$f.bak"
    echo "  (se reemplaza la receta anterior; copia en $name.md.bak)"
  fi
  {
    printf '# %s\n' "$name"
    printf '<!-- receta: la secuencia que FUNCIONO. Guardada %s -->\n\n' "$(date +%Y-%m-%d)"
    printf '%s\n' "$body"
  } > "$f"
  echo "  saved -> $f   ($(grep -c '' "$f") lineas; 0 tokens hasta que alguien la busque)"
  local idx="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")/_memory_index.py"
  [ -f "$idx" ] && (OPENCODE_MEMORY_DIR="$MEM" python3 "$idx" embed >/dev/null 2>&1 &)
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

# Cuantas entradas hay en total (decide si el indice vale la pena).
mem_size() {
  { cat "$PREFS" "$TOPICS"/*.md "$RECIPES"/*.md "$REPO_MEM" 2>/dev/null || true; } | grep -c '^- ' || true
}

cmd_search() {
  [ $# -ge 1 ] || { usage; exit 1; }
  # Escala sola: con pocas entradas, palabras+sinonimos (126 ms). A partir de
  # MEMORY_INDEX_MIN, el indice SQLite (FTS5, ranking BM25). Y si el lexico no
  # encuentra nada y hay embedder, el nivel vectorial — que cuesta 1-3 s de
  # arranque, asi que solo se paga cuando lo rapido ya fallo.
  local idx="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")/_memory_index.py"
  local min=${MEMORY_INDEX_MIN:-150}
  # El indice hibrido (FTS5 + vectorial con el embedder local) es el camino
  # normal: mide 92% de acierto frente al 79% del lexico con tabla de sinonimos
  # y el 54% de FTS5 solo (test/memory-retrieval.py). Se usa si hay embedder
  # —aunque haya pocos hechos— o si el corpus ya es grande. El nivel de abajo
  # queda como respaldo para cuando no hay ni indice ni red.
  if [ -f "$idx" ]; then
    if [ -n "${MEMORY_FORCE_INDEX:-}" ] || [ "$(mem_size)" -ge "$min" ] || OPENCODE_MEMORY_DIR="$MEM" python3 "$idx" has-embedder 2>/dev/null; then
      OPENCODE_MEMORY_DIR="$MEM" python3 "$idx" search "$@" && return 0
    fi
  fi
  local files=()
  [ -f "$PREFS" ] && files+=("$PREFS")
  for f in "$TOPICS"/*.md; do [ -f "$f" ] && files+=("$f"); done
  for f in "$RECIPES"/*.md; do [ -f "$f" ] && files+=("$f"); done
  [ -f "$REPO_MEM" ] && files+=("$REPO_MEM")
  [ -f "$PROGRESS" ] && files+=("$PROGRESS")
  [ ${#files[@]} -gt 0 ] || { echo "no memory yet"; return 0; }
  local rc=0
  python3 - "$SEARCH_MAX" "$MEM" "$@" -- "${files[@]}" <<'PY' || rc=$?
import sys,re,unicodedata
args=sys.argv[1:]; mx=int(args[0]); mem=args[1]; sep=args.index("--")
raw=args[2:sep]; files=args[sep+1:]

# Respaldo sin indice ni red: coincidencia por palabras, acentos ignorados y
# compuestos partidos (auth/login -> auth, login). NO hay tabla de sinonimos:
# se quito el 2026-09-25 porque el hibrido FTS5+vectorial acierta 92% sin ella
# frente al 79% que daba con tabla (test/memory-retrieval.py, 24 preguntas).
# Este nivel solo actua cuando no hay indice ni embedder; entonces vale mas una
# regla simple que 45 lineas de vocabulario que alguien tiene que mantener.
def fold(t):
    t=unicodedata.normalize("NFD",t.lower())
    return "".join(c for c in t if unicodedata.category(c)!="Mn")

STOP={"que","cual","cuales","como","donde","cuando","quien","quienes","por","para","con","sin","del","los","las","una","este","esta","esto","debe","puedo","puede","hay","the","what","which","where","who","how","does","should","and","for","with","from","this","that"}
terms=[fold(t) for t in raw if fold(t) not in STOP] or [fold(t) for t in raw]

def words(line):
    ws=set(re.findall(r"[a-z0-9._/-]+", fold(line)))
    for w in list(ws):
        ws |= {p for p in re.split(r"[./_-]+", w) if len(p) > 1}
    return ws

def matches(t, ws):
    if t in ws: return True
    return len(t) >= 5 and any(w.startswith(t) or t in w for w in ws)

hits=[]
for f in files:
    try: lines=open(f,encoding="utf8",errors="replace").read().splitlines()
    except Exception: continue
    for i,l in enumerate(lines,1):
        if not l.strip() or l.startswith(("#","<!--")): continue
        ws=words(l)
        score=sum(1 for t in terms if matches(t,ws))
        if score: hits.append((-score,f,i,l.strip()))
hits.sort()
if not hits:
    print("no match in memory for:"," ".join(raw))
    sys.exit(3)          # 3 = nada encontrado: memory.sh prueba el nivel vectorial
for n,f,i,l in hits[:mx]:
    short=f.replace(mem+"/","memory/") if f.startswith(mem) else f
    print(f"{short}:{i}: {l}")
if len(hits)>mx: print(f"  … {len(hits)-mx} more; add terms to narrow")
PY
  # Nada por palabras: ultimo recurso, busqueda por significado (si esta montada).
  if [ "$rc" = "3" ] && [ -f "$idx" ] && [ -x "${MEMORY_VENV:-$HOME/.cache/opencode-memory-venv}/bin/python" ]; then
    echo "  probando por significado (embeddings)..."
    OPENCODE_MEMORY_DIR="$MEM" python3 "$idx" search "$@"
  fi
  return 0
}

cmd_show() {
  local what="${1:-all}"
  case "$what" in
    pref|prefs)  cat "$PREFS" 2>/dev/null || echo "no preferences yet" ;;
    repo)        cat "$REPO_MEM" 2>/dev/null || echo "no repo memory yet ($REPO_MEM)" ;;
    topics)      cmd_index ;;
    recipes)     for f in "$RECIPES"/*.md; do [ -f "$f" ] && { echo "=== $(basename "$f" .md)"; cat "$f"; echo; }; done; [ -d "$RECIPES" ] || echo "no recipes yet" ;;
    all)
      echo "## $PREFS"; cat "$PREFS" 2>/dev/null || echo "(none)"
      echo; echo "## topics"; cmd_index
      echo; echo "## $REPO_MEM"; cat "$REPO_MEM" 2>/dev/null || echo "(none)" ;;
    *)
      if [ -f "$TOPICS/$what.md" ]; then cat "$TOPICS/$what.md"
      elif [ -f "$RECIPES/$what.md" ]; then cat "$RECIPES/$what.md"
      else echo "no topic or recipe '$what'. Existing:" >&2; cmd_index >&2; exit 1; fi ;;
  esac
}

cmd_index() {
  local any=0
  echo "  topics:"
  for f in "$TOPICS"/*.md; do
    [ -f "$f" ] || continue; any=1
    printf '    %s (%s facts)\n' "$(basename "$f" .md)" "$(grep -c '^- ' "$f" || true)"
  done
  [ $any -eq 1 ] || echo "    (none yet)"
  any=0
  echo "  recipes:"
  for f in "$RECIPES"/*.md; do
    [ -f "$f" ] || continue; any=1
    printf '    %s (%s lines) — %s\n' "$(basename "$f" .md)" "$(grep -c '' "$f")" "$(grep -m1 '^[A-Za-z0-9]' "$f" | cut -c1-60)"
  done
  [ $any -eq 1 ] || echo "    (none yet)"
}

# Un hecho que nombra un fichero o un comando que ya no existe es PEOR que no
# tenerlo: el modelo lo lee como verdad. `check` los encuentra para curarlos.
cmd_check() {
  local files=()
  [ -f "$PREFS" ] && files+=("$PREFS")
  for f in "$TOPICS"/*.md "$RECIPES"/*.md; do [ -f "$f" ] && files+=("$f"); done
  [ -f "$REPO_MEM" ] && files+=("$REPO_MEM")
  [ ${#files[@]} -gt 0 ] || { echo "no memory yet"; return 0; }
  python3 - "$MEM" "${files[@]}" <<'PY'
import sys,re,os,shutil,subprocess
mem=sys.argv[1]; files=sys.argv[2:]
repo=os.path.realpath(os.path.join(mem,".."))
stale=0
for f in files:
    for i,l in enumerate(open(f,encoding="utf8",errors="replace").read().splitlines(),1):
        if not l.strip() or l.startswith(("#","<!--")): continue
        bad=[]
        # ficheros del repo nombrados con ruta (bin/x.sh, plugin/y.ts, skill/z/SKILL.md)
        for m in re.findall(r"\b((?:bin|plugin|rules|skill|agent|memory|mcporter|command|templates|test)/[\w./-]+)", l):
            if not os.path.exists(os.path.join(repo,m)): bad.append(m)
        # comandos propios del repo
        for m in set(re.findall(r"\b(\w+\.sh)\b", l)):
            if not (shutil.which(m) or os.path.exists(os.path.join(repo,"bin",m))): bad.append(m)
        # binarios externos que la memoria da por instalados
        for m in set(re.findall(r"\b(mcporter|herdr|gh|acli|ntn|engram|opencode)\b", l)):
            if not shutil.which(m): bad.append(m+" (not installed)")
        if bad:
            stale+=1
            short=f.replace(mem+"/","memory/")
            print(f"  {short}:{i}: nombra {', '.join(sorted(set(bad)))}")
            print(f"      {l.strip()[:130]}")
print(f"  {stale} entrada(s) nombran algo que ya no existe" if stale else "  todo lo que la memoria nombra existe")
if stale: print("  Corrige o borra esas lineas: un hecho obsoleto se lee como verdad.")
PY
}

[ $# -lt 1 ] && { usage; exit 1; }
what="$1"; shift || true
case "$what" in
  save)    cmd_save "$@" ;;
  promote) cmd_promote "$@" ;;
  search)  cmd_search "$@" ;;
  recipe)  cmd_recipe "$@" ;;
  check)   cmd_check ;;
  show)    cmd_show "$@" ;;
  index)
    case "${1:-}" in
      --build|--embed|--stats)
        idx="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")/_memory_index.py"
        OPENCODE_MEMORY_DIR="$MEM" python3 "$idx" "${1#--}" ;;
      "") cmd_index ;;
      *) usage; exit 1 ;;
    esac ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
