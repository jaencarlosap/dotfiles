// ─────────────────────────────────────────────────────────────────────────
// anti-slop-guard — convierte REGLAS del prompt en RESTRICCIONES del entorno.
//
// Por que existe: una regla en el prompt cuesta tokens en CADA turno y el
// modelo la cumple "casi siempre". Un hook cuesta 0 tokens y la cumple SIEMPRE.
// Todo lo que este plugin impide se puede borrar de rules/*.md.
//
// VERIFICADO en v1.18.19 (probe con hooks reales):
//   - `permission.ask` NO se dispara si el permiso esta en "allow" (nuestro
//     caso: edit/bash en allow). Enforcement por ahi seria un no-op silencioso.
//   - `tool.execute.before` lanzando una excepcion SI aborta la herramienta, y
//     el mensaje de error llega al modelo, que reacciona y corrige solo.
//     Medido: bloqueado un `write` sobre fichero existente -> el modelo hizo
//     `read` + `edit` por su cuenta. El fichero sobrevivio.
//
// OJO con el texto del error: en la prueba el modelo COPIO una ruta truncada
// que aparecia en el mensaje. Por eso aqui los mensajes usan rutas RELATIVAS
// y cortas, y dicen exactamente que hacer.
//
// Kill switch:  OPENCODE_GUARD_OFF=1
// ─────────────────────────────────────────────────────────────────────────

import { existsSync, readFileSync, readdirSync, statSync } from "fs"
import { relative, isAbsolute, resolve, basename, dirname } from "path"
import { spawnSync } from "child_process"

// Ficheros que el modelo crea "por ayudar" y nadie pidio (rules §3).
// README.md NO esta: se pide de verdad demasiado a menudo como para bloquearlo.
const SLOP = /^(RESUME|CHANGES|CHANGELOG|ANALYSIS|SUMMARY|NOTES|REPORT|IMPLEMENTATION|OVERVIEW)[-_A-Z]*\.mde?$/i
// Duplicados versionados: foo_v2.py, foo_new.ts, foo copy.go, foo.bak (rules §2).
// OJO: el patron por si solo da FALSOS POSITIVOS — `brand_new.go` o `is_new.ts`
// son nombres legitimos. Lo que delata a un duplicado no es el sufijo, es que
// EXISTA el original al lado. Por eso solo se bloquea si `foo.ext` ya esta ahi.
const DUPE = /^(.*?)(_v\d+|_new|_final|_old|_copy| copy|\.bak|\.orig)(\.[a-z0-9]+)?$/i

// ── Comandos que NO existen: el fallo mas caro del modelo pequeño ────────
//
// Patron observado DOS veces en el mismo dia con qwen3.5-9b-mtp, y las dos
// acabaron en bucle infinito:
//
//   $ webfetch "https://..." 2>/dev/null | grep -i optional | head -10
//   $ ripgrep --help 2>&1 | grep -i "max"
//
// `webfetch` es una HERRAMIENTA, no un comando. `ripgrep` se llama `rg`. En los
// dos casos bash escribe "command not found" por STDERR... y el propio modelo
// habia puesto `2>/dev/null` o `| grep`, que se lo traga. Lo que le vuelve es
// SALIDA VACIA, que el interpreta como "no hay resultados" -> reformula la
// query -> mismo comando -> vacio otra vez. Uno de esos bucles llego a **229
// pasos** antes de matarlo a mano.
//
// La leccion no es "el modelo es tonto": es que un error convertido en vacio es
// indistinguible de un resultado vacio. Aqui se convierte de vuelta en error.
const SHELL_KEYWORDS = new Set([
  "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
  "case", "esac", "function", "select", "in", "time", "!", "{", "}", "(", ")",
  "cd", "echo", "printf", "export", "set", "unset", "shift", "source", ".", ":",
  "true", "false", "test", "[", "[[", "eval", "exec", "exit", "return", "local",
  "read", "readonly", "declare", "typeset", "let", "alias", "unalias", "type",
  "hash", "trap", "wait", "jobs", "bg", "fg", "kill", "umask", "ulimit", "pwd",
  "getopts", "command", "builtin", "break", "continue", "times",
])

// El PATH del proceso del plugin NO es el del agente: el hook `shell.env` de
// slim-tools le añade el bin de opencode. Sin esto, `docs.sh` y `web.sh`
// pareceria que no existen y el guard bloquearia sus propias herramientas.
const GUARD_PATH = `${process.env.HOME}/.config/opencode/bin:${process.env.PATH ?? ""}`
const resolvable = new Map<string, boolean>()
function exists(cmd: string): boolean {
  const hit = resolvable.get(cmd)
  if (hit !== undefined) return hit
  const r = spawnSync("/bin/sh", ["-c", `command -v -- "$1" >/dev/null 2>&1`, "sh", cmd], {
    env: { ...process.env, PATH: GUARD_PATH },
    timeout: 3000,
  })
  const ok = r.status === 0
  resolvable.set(cmd, ok)
  return ok
}

// Sugerencias: nombres del PATH que empiezan igual. `ripgrep` -> `rg` no sale
// de aqui (no comparten prefijo largo), pero `pyth`, `nodemo` o `dockr` si.
function nearby(cmd: string): string[] {
  const stem = cmd.slice(0, 3).toLowerCase()
  if (stem.length < 3) return []
  const out = new Set<string>()
  for (const dir of GUARD_PATH.split(":")) {
    if (!dir) continue
    let entries: string[]
    try { entries = readdirSync(dir) } catch { continue }
    for (const e of entries) {
      if (e.toLowerCase().startsWith(stem) && e !== cmd) out.add(e)
      if (out.size >= 6) return [...out]
    }
  }
  return [...out]
}

// Trocea por separadores REALES: |, ||, &&, ;, newline — pero solo fuera de
// comillas y de $( ).
//
// ⚠️ ESTO NO ES PEDANTERIA. La primera version partia con
// `cmd.split(/\|\||&&|[|;\n]/)`, sin mirar comillas, y bloqueo esto:
//
//   curl -s localhost:8080/health && curl -v ... | grep -E "HTTP|status|ok"
//
// El `|` de DENTRO del regex partia el tramo, `status` quedaba de cabeza, no
// existe como comando -> BLOCKED. El agente estaba verificando su servidor y se
// comio un bloqueo por escribir una alternancia de grep. Un falso positivo aqui
// para al agente en seco, que es justo lo contrario de lo que queremos.
// Un heredoc (`cat > f <<'EOF' ... EOF`) mete CODIGO en el comando. Sin quitarlo,
// cada linea del cuerpo parece un comando: en un run real el modelo escribio un
// fichero JS con `cat <<EOF`, la linea `const now = new Date();` se tomo por un
// comando y el guard bloqueo la escritura. Fuera el cuerpo antes de trocear.
// NO exportar esto (ni nada que no sea `default`): opencode trata CUALQUIER
// named export del modulo como una factory de plugin y la INVOCA con su
// PluginInput. Exportarlas rompio el plugin ENTERO en el arranque:
//   ERROR failed to load plugin .../anti-slop-guard.ts error="cmd.split is not a function"
// El guard dejo de existir en silencio durante varios runs, y los tests
// seguian en verde porque importan `default` a mano. Ver test "solo exporta default".
function stripHeredocs(cmd: string): string {
  const lines = cmd.split("\n")
  const out: string[] = []
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    out.push(line)
    const m = line.match(/<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1/)
    if (!m) continue
    const delim = m[2]
    i++
    while (i < lines.length && lines[i].trim() !== delim) i++
  }
  return out.join("\n")
}

function segments(cmd: string): string[] {
  const out: string[] = []
  let cur = ""
  let quote: '"' | "'" | null = null
  let depth = 0 // $( ... ) y ` ... `
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i]
    if (quote) {
      cur += c
      if (c === quote && cmd[i - 1] !== "\\") quote = null
      continue
    }
    if (c === '"' || c === "'") { quote = c; cur += c; continue }
    if (c === "$" && cmd[i + 1] === "(") { depth++; cur += "$("; i++; continue }
    if (c === "(" && depth > 0) { depth++; cur += c; continue }
    if (c === ")" && depth > 0) { depth--; cur += c; continue }
    if (depth === 0 && (c === "|" || c === ";" || c === "\n" || (c === "&" && cmd[i + 1] === "&"))) {
      if (c === "&" || (c === "|" && cmd[i + 1] === "|")) i++
      out.push(cur); cur = ""
      continue
    }
    cur += c
  }
  out.push(cur)
  return out
}

// Primera palabra de cada tramo. Se ignora todo lo que no sea un nombre pelado:
// variables, rutas, sustituciones, asignaciones (`FOO=1 cmd`), redirecciones y
// comodines. Ante la duda, NO se bloquea.
function unknownCommands(cmd: string): string[] {
  const bad: string[] = []
  for (const seg of segments(stripHeredocs(cmd))) {
    const tokens = seg.trim().split(/\s+/).filter(Boolean)
    let head = tokens[0]
    // Saltar asignaciones al principio: FOO=1 BAR=2 cmd
    let i = 0
    while (head && /^[A-Za-z_][A-Za-z0-9_]*=/.test(head)) head = tokens[++i]
    if (!head) continue
    if (head === "sudo" || head === "env" || head === "nohup" || head === "xargs") head = tokens[i + 1]
    if (!head) continue
    if (!/^[A-Za-z][A-Za-z0-9._+-]*$/.test(head)) continue   // rutas, $vars, $(...), quotes
    if (SHELL_KEYWORDS.has(head)) continue
    if (exists(head)) continue
    if (!bad.includes(head)) bad.push(head)
  }
  return bad
}

// ── Lecturas que se comen el contexto ───────────────────────────────────
//
// Medido en `stremio-iptv-addon` el 2026-09-09, sesion ses_f77dc102: 40
// llamadas, 121.519 chars de salida, DOS compactaciones en 8 minutos. Cuatro
// lecturas se llevaron el 71% del espacio util:
//
//   23.559  read addon/src/index.js            (439 lineas, entero)
//   18.641  read addon/src/latino/index.js     (353 lineas, entero)
//   16.069  bash docker logs --since ... 2>&1  (sin tail, sin filtro)
//   15.630  bash cat addon/src/pocketbase.js   (466 lineas, entero)
//
// Y `sololatino.js` se leyo DOS veces, con `cat` y luego con `read`: 17.315
// chars por el mismo contenido.
//
// Las reglas ya prohibian esto ("Never cat a file over 200 lines"). No sirvio:
// en 187 sesiones hay 506 `cat` en 33 sesiones distintas. Una regla en el
// prompt es una sugerencia; un guard es un limite. Por eso esto es un hook.
//
// El mensaje dice el COSTE en tokens, no solo "no lo hagas": lo que el modelo
// no puede estimar es cuanto de su presupuesto se esta gastando.
const BIG_CAT = 8_000        // ~200 lineas, el limite que ya decian las reglas
const BIG_READ = 12_000      // ~4.000 tokens: el 10% del espacio util de un turno
const CHARS_PER_TOKEN = 3.03 // medido en este setup (8 skills = 4.230 chars = 1.396 tok)
const USABLE_TOKENS = 40_000 // context 66.000 - output 14.000 - prompt fijo ~11.300

function fileSize(f: string): number {
  try { const st = statSync(f); return st.isFile() ? st.size : 0 } catch { return 0 }
}
// Lo que cuesta un `read` NO es el tamaño en disco: la herramienta numera las
// lineas, y ese prefijo entra en el contexto igual que el codigo.
//
// Medido en T2c (2026-09-09): docs/providers.md son 11.199 chars en disco y
// 285 lineas -> se colo por debajo del umbral de 12.000, pero la salida real
// fueron 12.528 chars. Un 12% mas. Contando por lo bajo, el guard deja pasar
// justo los ficheros que estan en la frontera.
function readCost(f: string): number {
  const bytes = fileSize(f)
  if (!bytes) return 0
  try {
    let lines = 0
    for (const c of readFileSync(f, "utf8")) if (c === "\n") lines++
    return bytes + lines * 7   // "  123\t" de media
  } catch { return bytes }
}
function costOf(bytes: number): string {
  const tok = Math.round(bytes / CHARS_PER_TOKEN)
  return `${bytes} chars \u2248 ${tok} tokens, ${Math.round((100 * tok) / USABLE_TOKENS)}% of your working context`
}
// `cat f | head -50` esta acotado y no se bloquea; `cat f` a pelo, si.
const BOUNDED = /\|\s*(head|tail|grep|rg|wc|jq|sed|awk|python3?|sort|uniq|cut)\b/
// `docker logs` sin --tail, sin --since y sin tuberia que lo acote.
const DOCKER_LOGS = /\bdocker\s+(compose\s+)?logs\b/

// El fichero de progreso se reescribe entero a proposito en cada paso, asi que
// nunca se bloquea. Se aceptan las DOS convenciones: `.agent/progress.md` (la
// actual, en un directorio gitignored) y `.agent_progress.md` (la anterior).
//
// Esto era un BUG REAL y grave: el plugin solo conocia la ruta vieja, asi que
// en un RESUME el guard BLOQUEABA el fichero de progreso — el agente lo lee con
// `cat` (bash, que no cuenta como "leido" porque no pasa por la tool `read`) y
// al reescribirlo se lo comia el bloqueo. Rompia justo el protocolo de resume
// que este setup existe para sostener.
// ── Rutas absolutas reconstruidas de memoria ─────────────────────────────
// Los DOS modelos lo hacen, y es de los fallos mas silenciosos que hay:
//
//   qwen3.5-9b-mtp: `/Users/jaencarlos-Documents-personal-dotfiles/...`
//                   (se comio las barras) -> el write fallo, reintento, y acabo
//                   diciendo que habia escrito el fichero.
//   gpt-oss-20b:    escribio un proyecto entero en
//                   `.../7cbe5611-1f12-4e03-.../oss-newproj/time_script/`
//                   cuando el UUID real acaba en `4d03`. Una letra. El write
//                   CREO el arbol fantasma, dijo "Wrote file successfully" y el
//                   modelo reporto la tarea como terminada. El directorio que el
//                   usuario mira se quedo vacio.
//
// La firma comun no es "ruta absoluta" (escribir en /tmp es legitimo): es una
// ruta absoluta FUERA del proyecto cuyo directorio padre NO EXISTE. Nadie
// escribe a proposito en un arbol que no existe fuera de su proyecto; un dedazo
// en una ruta larga, si.
function phantomPath(file: string, directory: string): string | null {
  if (!isAbsolute(file)) return null
  const inProject = resolve(file).startsWith(resolve(directory) + "/")
  if (inProject) return null
  const parent = dirname(resolve(file))
  if (existsSync(parent)) return null
  return parent
}

// ── El fallo cronico nº2: `read` de una ruta que no existe ───────────────
// MEDIDO en la misma base: 31 veces en 18 SESIONES distintas ("File not found").
// El modelo deduce la ruta ("debe estar en src/utils/") en vez de buscarla. El
// error de opencode dice "no existe" y ya; aqui se le devuelve DONDE esta el
// fichero que buscaba, que es lo que convierte dos turnos perdidos en uno util.
// Un modelo pequeño no encuentra la diferencia entre dos rutas largas que se
// parecen: `scrapper-puppeteer` vs `scraper-puppeteer` es UNA letra en medio
// de 47 caracteres, y la releyo 92 veces sin verla. Señalar el SEGMENTO que
// falla, solo, convierte el diff en algo de una palabra.
function segmentDiff(wrong: string, right: string): string {
  const w = wrong.split("/").filter(Boolean)
  const r = right.split("/").filter(Boolean)
  for (let i = 0; i < Math.max(w.length, r.length); i++) {
    if (w[i] === r[i]) continue
    if (w[i] && r[i]) return ` The wrong part is the directory name: you wrote "${w[i]}", it is "${r[i]}".`
    return ""
  }
  return ""
}

const SKIP_DIRS = new Set(["node_modules", ".git", "dist", "build", "vendor", ".venv", "target", ".next", "__pycache__"])
function findByName(root: string, name: string, limit = 5): string[] {
  const out: string[] = []
  const queue = [root]
  let seen = 0
  while (queue.length && out.length < limit && seen < 4000) {
    const dir = queue.shift()!
    let entries: any[]
    try { entries = readdirSync(dir, { withFileTypes: true }) } catch { continue }
    for (const e of entries) {
      seen++
      if (seen > 4000) break
      if (e.isDirectory()) {
        if (!SKIP_DIRS.has(e.name) && !e.name.startsWith(".")) queue.push(resolve(dir, e.name))
      } else if (e.name === name) {
        out.push(resolve(dir, e.name))
        if (out.length >= limit) break
      }
    }
  }
  return out
}

// ── El fallo cronico nº1 del modelo pequeño: `edit` que no casa ──────────
//
// MEDIDO sobre la base de datos de sesiones (156 sesiones, 34.198 parts):
//
//   35 x "Could not find oldString in the file" — en 15 SESIONES distintas
//   10 x "No changes to apply: oldString and newString are identical"
//
// Es el error real mas repetido despues de los bucles, y es cronico, no una
// mala racha. La causa es siempre la misma: el modelo escribe el `oldString` de
// memoria — con la indentacion, las comillas o el espaciado que el cree — en vez
// de copiarlo del fichero.
//
// El error de opencode ("Could not find oldString...") es CORRECTO pero inutil:
// no dice en que se diferencia. Aqui se adelanta el fallo con la linea REAL del
// fichero, que es lo unico que el modelo necesita para arreglarlo en un intento.
function editDiagnosis(content: string, oldString: string): string | null {
  if (content.includes(oldString)) return null
  const lines = content.split("\n")
  const first = oldString.split("\n").find((l) => l.trim().length > 3)?.trim()
  if (!first) return "The oldString is empty or only whitespace."

  // ¿Esta la linea pero con OTRA indentacion/espaciado? Es el caso mas comun.
  const exact = lines.findIndex((l) => l.trim() === first)
  if (exact >= 0)
    return (
      `That text IS in the file at line ${exact + 1}, but not exactly as you wrote it — ` +
      `whitespace or indentation differ. The real line is:\n  ${JSON.stringify(lines[exact])}\n` +
      `Copy it verbatim (note the leading whitespace shown in the quoted form).`
    )
  // ¿Hay algo parecido? Se ofrece como pista, no como certeza.
  const near = lines
    .map((l, i) => ({ i, l, score: l.trim().length && first.length ? overlap(l.trim(), first) : 0 }))
    .filter((x) => x.score >= 0.75)
    .sort((a, b) => b.score - a.score)
    .slice(0, 2)
  if (near.length)
    return (
      `Not found. The closest lines in the file are:\n` +
      near.map((x) => `  line ${x.i + 1}: ${JSON.stringify(x.l)}`).join("\n") +
      `\nIf one of those is what you meant, copy it exactly as shown.`
    )
  return `Nothing resembling that text is in the file (${lines.length} lines). You may have the wrong file.`
}

// Solape de caracteres, barato y suficiente para "se parece a esta linea".
function overlap(a: string, b: string): number {
  const s = new Set(a.split(/\s+/))
  const t = b.split(/\s+/)
  if (!t.length) return 0
  return t.filter((w) => s.has(w)).length / t.length
}

// ── Poner un test en verde apagandolo ────────────────────────────────────
// El fallo mas caro que puede cometer un agente autonomo: no es romper algo, es
// hacer que PAREZCA que funciona. Un test saltado da build verde, informe de
// "todo correcto", y el defecto sigue vivo.
//
// Verificado antes de escribir esto: NI las reglas (engineering-discipline) NI
// el prompt de `auto` lo prohiben en ningun sitio. Era un agujero de verdad.
//
// Se BLOQUEA, no se avisa: un aviso llega DESPUES de escribir el fichero, y
// para cuando el modelo lo lee el test ya esta apagado. Si de verdad hay que
// saltar uno, lo pide el usuario y se hace con OPENCODE_GUARD_OFF=1.
const SKIP_MARKER =
  /(\bt\.Skip(Now)?\s*\(|\bt\.SkipIf\b|\b(it|test|describe|context)\.(skip|todo)\s*\(|\bx(it|describe|test)\s*\(|@pytest\.mark\.(skip|xfail)|\bunittest\.skip\b|#\[ignore\]|@Ignore\b|@Disabled\b|\.only\s*\()/
// Solo aplica a ficheros que SON tests: apagar algo en `main.go` no es esto.
const TEST_FILE = /(^|[\/_.-])(test|tests|spec|specs|__tests__)([\/_.-]|$)|_test\.[a-z]+$|\.(test|spec)\.[a-z]+$/i

// UNA sola ruta canonica. `.agent_progress.md` se sigue aceptando en silencio
// como red (hay repos con sesiones a medias), pero ya no se nombra en ninguna
// instruccion: nombrar dos rutas es como acaban existiendo tres.
const PROGRESS = [".agent/progress.md", ".agent_progress.md"]

// Variantes que el modelo teclea mal y que ACABAN EN EL REPO. `.agents/` (con
// `s`) entro commiteado en stremio-iptv-addon (488524b) por este camino: un
// typo crea un directorio nuevo, nadie lo mira, y el repo acaba con tres sitios
// donde buscar el estado. Mismo patron que `scrapper` vs `scraper`.
const PROGRESS_TYPOS = [
  ".agents/progress.md",
  ".agent/progress.MD",
  "agent/progress.md",
  ".opencode/progress.md",
  ".claude/progress.md",
]

// ── Fontaneria MCP: bloquearla, no pedir que no se use ───────────────────
// opencode inyecta estas 3 tools en TODOS los agentes en cuanto hay un
// servidor MCP. Los servidores de aqui exponen TOOLS, no RESOURCES ("MCP
// server jiraAdmin does not support resources"), asi que SIEMPRE devuelven
// vacio.
//
// El problema no es el gasto (197 tok/turno), es que ENGAÑAN al modelo. Con
// un 20B la eleccion de herramienta es coincidencia de nombres: le pides
// "revisa los MCP", tu frase lleva "MCP", y hay tools que se llaman
// `list_mcp_*` -> las llama, no obtiene nada, y responde que no hay nada
// disponible... con `jiraAdmin_confluence-search` en su lista, funcionando.
//
// Lo intentado y DESCARTADO (comprobado, no supuesto):
//   - `tools: { list_mcp_resources: false }` -> NO las quita (las del servidor
//     si se filtran, estas no).
//   - `tool.definition` para acortar su descripcion -> el hook NO se dispara
//     para tools de MCP, solo para las nativas.
//   - Decirselo en el prompt -> se cumplio a medias. Es probabilistico.
//
// `tool.execute.before` SI se dispara para tools MCP y lanzar aborta la
// llamada... pero SOLO A VECES. Medido: opencode valida el argumento `server`
// ANTES de ejecutar los hooks. Si el modelo manda `server: ""` el hook corre y
// este bloqueo funciona; si manda `server: "all"` (o cualquier nombre que no
// existe) opencode falla primero con su propio error y el hook nunca llega a
// ejecutarse.
//
// O sea: esto ayuda, pero NO es una pared. Se deja porque cuando dispara
// redirige bien y no cuesta nada, no porque cierre el problema.
//
// EL PROBLEMA DE FONDO NO ES ARREGLABLE AQUI: "¿que MCPs tengo?" es una
// pregunta de INTROSPECCION, y este modelo no sabe enumerar sus propias
// herramientas. Da igual lo que devuelvan estas 3 tools. USAR el MCP funciona
// perfectamente (`jiraAdmin_confluence-search` -> 25 resultados reales);
// INVENTARIARLO no. Para inventariar: `make mcp`, sin modelo de por medio.
const MCP_PLUMBING = new Set([
  "list_mcp_resources",
  "list_mcp_resource_templates",
  "read_mcp_resource",
])
const isProgress = (rel: string, base: string) =>
  PROGRESS.includes(rel.replace(/\\/g, "/")) || base === ".agent_progress.md"

// El permiso `read` deniega *.env (verificado en vivo), pero `bash` esta en
// "allow", asi que `cat .env` se lo saltaba entero. Taparlo con patrones de
// bash en opencode.jsonc seria un juego de topos (less, head, xxd, awk...),
// asi que se mira el comando de verdad. Best-effort, no una caja fuerte:
// un `source .env && echo $X` sigue siendo posible. Cubre lo habitual.
const ENV_FILE = /(^|[\s'"/=])\.?[\w.-]*\.env(?!\.example)\b/
const READS_FILES = /\b(cat|less|more|head|tail|bat|nl|od|xxd|strings|base64|grep|rg|awk|sed|cut|tr|sort|uniq|tee|cp|mv|scp|curl|jq|python3?|node)\b/

// Declaraciones de simbolos, para detectar borrados accidentales (rules §7).
const DECL = /^[ \t]*(?:export\s+)?(?:async\s+)?(func|def|class|fn|function|type|interface|const|var|let)\s+([A-Za-z_][\w]*)/gm

function symbols(s: string): Set<string> {
  const out = new Set<string>()
  for (const m of s.matchAll(DECL)) out.add(`${m[1]} ${m[2]}`)
  return out
}

// Path relativa y corta: lo que el modelo vera y potencialmente copiara.
function short(file: string, dir: string): string {
  const abs = isAbsolute(file) ? file : resolve(dir, file)
  const rel = relative(dir, abs)
  return rel && !rel.startsWith("..") ? rel : basename(abs)
}

export default (async ({ directory }: any) => {
  // sessionID -> ficheros que el agente YA ha leido en esta sesion.
  const seen = new Map<string, Set<string>>()
  // callID -> contenido del fichero ANTES de un `write`, para detectar borrados.
  // Un `write` de fichero entero puede eliminar simbolos sin que `edit` lo vea:
  // pasó en la prueba end-to-end (un write dejo `package main` y se llevo por
  // delante `func Existing()` sin ningun aviso).
  const preWrite = new Map<string, string>()
  // sid -> "fichero|offset|limit" -> mtime cuando se leyo.
  //
  // ⚠️ LA CLAVE LLEVA EL RANGO, y esa es toda la leccion. La v1 guardaba solo
  // el fichero, y en la primera prueba real (T2, 2026-09-09) bloqueo 13 de 18
  // lecturas: el modelo hacia exactamente lo que el OTRO guard le pide —
  // `read` con offset/limit, avanzando por el fichero — y este le decia "ya lo
  // leiste". Le monto un bucle: reintento 142/180, 142/120, 142/120, 142/60.
  //
  // Leer OTRO tramo del mismo fichero es legitimo y es el camino que queremos.
  // Lo que se bloquea es pedir EL MISMO tramo dos veces sin que el fichero
  // haya cambiado.
  const readMtime = new Map<string, Map<string, number>>()

  // ── El guard tiene que romper SUS PROPIOS bucles ───────────────────────
  //
  // Fallo real (2026-09-09, sesion ses_f779a0b74): el modelo pidio
  // `scrapper-puppeteer/embed-resolver.js` — una `p` de mas — y el guard le
  // contesto, correctamente, con la ruta buena. Lo reintento **92 veces
  // identicas en 7 minutos**, hasta que el usuario mato el proceso a mano.
  //
  // Y el loop-breaker, que existe justo para esto, **no disparo ni una vez**:
  // opencode carga los plugins por nombre, `anti-slop-guard` va antes que
  // `loop-breaker`, y como este guard LANZA en `tool.execute.before`, la
  // llamada nunca llega al hook del loop-breaker. Es decir: cada bloqueo de
  // este fichero desactivaba la red de seguridad justo cuando hacia falta.
  //
  // Por eso la escalada vive AQUI, donde se lanza, y no depende del orden de
  // carga de nadie. Un bloqueo que se repite deja de ser una explicacion y
  // pasa a ser un alto.
  const blockHits = new Map<string, Map<string, number>>()
  function refuse(sid: string, key: string, first: string, fix: string): never {
    if (!blockHits.has(sid)) blockHits.set(sid, new Map())
    const m = blockHits.get(sid)!
    const n = (m.get(key) ?? 0) + 1
    m.set(key, n)
    if (n >= 5)
      throw new Error(
        `STOP. This exact call has been blocked ${n} times in this session and it will NEVER ` +
          `succeed — repeating it cannot change the outcome. ${fix} ` +
          `If you already have what you need, answer the user now instead of calling another tool.`,
      )
    if (n >= 3)
      throw new Error(`BLOCKED (${n}x — you are repeating a call that cannot work). ${fix}`)
    throw new Error(first)
  }
  const rangeKey = (abs: string, a: any) => `${abs}|${a?.offset ?? ""}|${a?.limit ?? ""}`
  const mark = (sid: string, f?: string) => {
    if (!f) return
    if (!seen.has(sid)) seen.set(sid, new Set())
    seen.get(sid)!.add(isAbsolute(f) ? f : resolve(directory, f))
  }
  const wasRead = (sid: string, f: string) =>
    seen.get(sid)?.has(isAbsolute(f) ? f : resolve(directory, f)) ?? false

  return {
    "tool.execute.before": async (input: any, output: any) => {
      if (process.env.OPENCODE_GUARD_OFF === "1") return
      const tool = input?.tool

      // Fontaneria MCP: cortar y redirigir a la herramienta que si sirve.
      // Mensaje CORTO y con nombres exactos: el modelo copia lo que lee.
      // El mensaje tiene que decirle QUE HACER, no solo que pare. Primera
      // version decia "llama a la tool directamente" y el modelo igualmente
      // respondio "no hay ningun MCP que puedas usar" mientras nombraba
      // `duckduckgo_search` en la misma frase. Ahora se le dice literalmente
      // como contestar.
      if (MCP_PLUMBING.has(tool))
        throw new Error(
          "BLOCKED: this tool always returns empty here and proves nothing. " +
            "MCP servers ARE configured and connected. Every tool in your list whose name has a " +
            "server prefix before an underscore (jiraAdmin_..., duckduckgo_...) IS a working MCP tool. " +
            "If the user asked which MCP servers exist, answer by listing those tool names from your " +
            "own tool list. If they asked you to DO something, call the matching tool now. " +
            "Never answer that no MCP servers are available.",
        )

      // `read` de una ruta inventada: decirle DONDE esta el fichero.
      if (tool === "read") {
        const f = String(output?.args?.filePath ?? "")
        if (f && !existsSync(f)) {
          const name = basename(f)
          const hits = findByName(directory, name).map((h) => short(h, directory))
          if (hits.length)
            refuse(
              input?.sessionID,
              `missing:${f}`,
              `BLOCKED: ${short(f, directory)} does not exist, but a file named ${name} does:\n` +
                hits.map((h) => `  ${h}`).join("\n") +
                segmentDiff(short(f, directory), hits[0]) +
                `\nUse one of those paths. Do not guess a third one.`,
              `Copy this path character by character: ${hits[0]}` + segmentDiff(short(f, directory), hits[0]),
            )
          refuse(
            input?.sessionID,
            `missing:${f}`,
            `BLOCKED: ${short(f, directory)} does not exist and no file named ${name} was found in this project. ` +
              `Do not guess another path: find it first with the glob tool (pattern "**/${name}") or ` +
              `\`grep -rn "<a symbol it contains>" . | head\`.`,
            `That file is not in this project. Run \`glob "**/${name}"\` — do not type another path from memory.`,
          )
        }

        // Relectura del MISMO fichero sin que haya cambiado: es contexto
        // pagado dos veces. Si lo editaste, el mtime cambio y pasa.
        const abs = isAbsolute(f) ? f : resolve(directory, f)
        const prevM = readMtime.get(input?.sessionID)?.get(rangeKey(abs, output?.args))
        if (prevM !== undefined && fileSize(abs) > 4_000) {
          let now = prevM
          try { now = statSync(abs).mtimeMs } catch {}
          if (now === prevM)
            throw new Error(
              `BLOCKED: you already read this exact range of ${short(f, directory)} in this session and the file ` +
                `has not changed. That content is still in your context — scroll back instead of paying for it twice. ` +
                `Reading a DIFFERENT range is fine: move offset past what you already have, or run ` +
                `\`grep -n "<symbol>" ${short(f, directory)}\` to jump straight to the line you need.`,
            )
        }

        // Fichero grande leido entero: la causa nº1 de compactar a los 8 min.
        const bytes = readCost(abs)
        const bounded = output?.args?.offset !== undefined || output?.args?.limit !== undefined
        if (bytes > BIG_READ && !bounded)
          refuse(
            input?.sessionID,
            `big:${abs}`,
            `BLOCKED: ${short(f, directory)} is ${costOf(bytes)}. Reading it whole is how a session ends up ` +
              `compacted before it has answered anything. Do one of these instead:\n` +
              `  grep -n "<the symbol you actually need>" ${short(f, directory)}\n` +
              `  read with offset/limit once grep tells you the line\n` +
              `Only read it whole if you genuinely need every line, and then say why.`,
            `Read it in pieces: call read on ${short(f, directory)} with offset 1 and limit 120, then move ` +
              `offset forward. The same call without offset will keep being refused.`,
          )
      }

      // bash: secretos, y comandos que no existen.
      if (tool === "bash") {
        const cmd = String(output?.args?.command ?? "")
        if (ENV_FILE.test(cmd) && READS_FILES.test(cmd))
          throw new Error(
            "BLOCKED: reading a .env file through bash. Secrets must not enter the conversation. Use .env.example, or ask the user for the value you need.",
          )
        // `docker logs` sin acotar: 40+ horas de salida sin estructura.
        if (DOCKER_LOGS.test(cmd) && !/--tail\b|--since\b/.test(cmd) && !BOUNDED.test(cmd))
          throw new Error(
            "BLOCKED: `docker logs` with no bound. These containers have days of output and it all lands " +
              "in your context. Add a bound: `--since 30m --tail 100`, and a `| grep -i <what you look for>`. " +
              "And check the project's AGENTS.md first: if it points at a structured log store (a database, " +
              "a log API), that is the source of truth and `docker logs` is the fallback, not the start.",
          )

        // `cat` de un fichero grande. Las reglas ya lo decian; 506 llamadas en
        // 33 sesiones dicen que una regla no basta.
        if (!BOUNDED.test(cmd)) {
          for (const seg of segments(stripHeredocs(cmd))) {
            const t = seg.trim().split(/\s+/).filter(Boolean)
            if (t[0] !== "cat" || seg.includes(">")) continue
            for (const a of t.slice(1)) {
              if (a.startsWith("-")) continue
              const f = isAbsolute(a) ? a : resolve(directory, a)
              const bytes = fileSize(f)
              if (bytes > BIG_CAT)
                throw new Error(
                  `BLOCKED: \`cat ${a}\` — that file is ${costOf(bytes)}. bash output goes straight into your ` +
                    `context and never comes back out. Use the tools that let you take only what you need:\n` +
                    `  grep -n "<symbol>" ${a}      to find the line\n` +
                    `  read tool with offset/limit  to read around it\n` +
                    `If you only wanted to know it exists, \`wc -l ${a}\` is enough.`,
                )
            }
          }
        }

        const missing = unknownCommands(cmd)
        if (missing.length) {
          const near = nearby(missing[0])
          throw new Error(
            `BLOCKED: \`${missing[0]}\` is not a command on this machine (checked with \`command -v\`). ` +
              `It did NOT return an empty result — it does not exist. Do not run it again, and do not hide ` +
              `the error with \`2>/dev/null\` or a \`| grep\`: that turns "command not found" into silence ` +
              `and you will loop. ` +
              (near.length ? `Similar commands on PATH: ${near.join(", ")}. ` : "") +
              `If you meant an opencode TOOL (webfetch, websearch, read, grep, glob, edit), call the tool ` +
              `directly — tools are not shell commands. To search the web from bash: \`web.sh search "..."\`, ` +
              `to read a page: \`web.sh read <url>\`, for a package: \`docs.sh npm|py|rs|go <name>\`.`,
          )
        }
        return
      }

      if (tool !== "write" && tool !== "edit") return
      const file: string | undefined = output?.args?.filePath
      if (!file || typeof file !== "string") return

      const rel = short(file, directory)
      // Un solo sitio para el estado. Se corta ANTES de crear el directorio.
      if (PROGRESS_TYPOS.includes(rel.replace(/\\/g, "/")))
        throw new Error(
          `BLOCKED: ${rel} is not the progress file. There is exactly ONE: \`.agent/progress.md\`. ` +
            `Writing here creates a second place to look for the state, and the next session will read the ` +
            `wrong one. Use .agent/progress.md — and note the directory is \`.agent\`, singular, no "s".`,
        )
      const base = basename(file)
      if (isProgress(rel, base)) return

      // Ruta absoluta fuera del proyecto y hacia un arbol inexistente.
      const phantom = phantomPath(file, directory)
      if (phantom)
        throw new Error(
          `BLOCKED: you are writing to an absolute path outside this project whose directory ` +
            `does not exist:\n  ${phantom}\n` +
            `That is almost always a path you retyped from memory with a typo — it happened twice ` +
            `here, once with a missing slash and once with a single wrong character in a UUID, and ` +
            `the file ended up in a folder nobody would ever look at.\n` +
            `Use a path RELATIVE to the project instead: filePath "subdir/file.ext". If you really ` +
            `do mean somewhere outside the project, create the directory first and say why.`,
        )

      // `edit` que no va a casar: fallar YA, con la linea real del fichero.
      if (input.tool === "edit") {
        const oldString = String(output?.args?.oldString ?? "")
        const newString = String(output?.args?.newString ?? "")
        if (oldString && oldString === newString)
          throw new Error(
            "BLOCKED: oldString and newString are identical, so this edit changes nothing. " +
              "Decide what the line should become and write that, or skip the edit.",
          )
        if (oldString && existsSync(file)) {
          let content = ""
          try { content = readFileSync(file, "utf8") } catch { content = "" }
          if (content && content.length < 2_000_000) {
            const why = editDiagnosis(content, oldString)
            if (why)
              throw new Error(
                `BLOCKED: this edit would fail — the oldString is not in ${rel} as written. ${why}\n` +
                  `Read the region first (read tool with offset/limit, or \`grep -n\`) and copy the text ` +
                  `from what you just read. Never retype it from memory, and never retry the same ` +
                  `oldString hoping it matches this time.`,
              )
          }
        }
      }

      // Apagar un test para que el build pase en verde.
      if (TEST_FILE.test(rel)) {
        const added = String(input.tool === "edit" ? (output?.args?.newString ?? "") : (output?.args?.content ?? ""))
        const removed = String(output?.args?.oldString ?? "")
        const marker = added.match(SKIP_MARKER)?.[0]
        if (marker && !SKIP_MARKER.test(removed))
          throw new Error(
            `BLOCKED: this edit adds \`${marker.trim()}\` to a test file. Skipping, ignoring or ` +
              `narrowing a test does not fix anything — it hides the defect behind a green build, ` +
              `which is worse than a red one because nobody looks again. ` +
              `A failing test is telling you either (a) the code is wrong — fix the code, or ` +
              `(b) the test is wrong — then say WHY in one sentence and change the assertion to what ` +
              `is actually correct, never to whatever the code happens to return. ` +
              `If you cannot do either, leave the test failing and report it. ` +
              `Load the skill \`failing-test\` for the procedure. ` +
              `If the USER explicitly asked you to skip it, do not just refuse: say that this guard ` +
              `blocks it and that they can re-run with OPENCODE_GUARD_OFF=1 if they still want it.`,
          )
      }

      // 1. Ficheros de relleno que nadie pidio.
      if (SLOP.test(base))
        throw new Error(
          `BLOCKED: do not create ${rel}. Summaries, reports and notes go in your chat answer, not on disk. If the user explicitly asked for this file, set OPENCODE_GUARD_OFF=1.`,
        )

      // 2. Duplicados versionados: solo si el original existe al lado.
      const dupe = base.match(DUPE)
      if (dupe) {
        const original = dupe[1] + (dupe[3] ?? "")
        const abs = isAbsolute(file) ? file : resolve(directory, file)
        const sibling = resolve(abs, "..", original)
        if (original && existsSync(sibling))
          throw new Error(
            `BLOCKED: ${original} already exists — edit it instead of creating ${rel}. Git is the backup, not a _v2 copy.`,
          )
      }

      // 3. Sobrescribir a ciegas un fichero que existe y que NO has leido.
      //    Sobrescribir DESPUES de leerlo si esta permitido: eso es una
      //    reescritura informada, no un "empiezo de cero".
      if (tool === "write" && existsSync(file) && !wasRead(input.sessionID, file))
        throw new Error(
          `BLOCKED: ${rel} already exists and you have not read it in this session. Read it first, then use the edit tool on the part you need to change. Never rewrite a whole file to change part of it.`,
        )

      // Write permitido sobre fichero existente: guarda el "antes" para poder
      // avisar si se lleva simbolos por delante.
      if (tool === "write" && existsSync(file)) {
        try { preWrite.set(input.callID, readFileSync(file, "utf8")) } catch {}
      }
    },

    "tool.execute.after": async (input: any, output: any) => {
      if (process.env.OPENCODE_GUARD_OFF === "1") return
      const sid = input?.sessionID
      const file: string | undefined = input?.args?.filePath

      // Leer (o editar con exito) cuenta como "ya lo conoces".
      if (input?.tool === "read" || input?.tool === "edit" || input?.tool === "write") mark(sid, file)
      if (input?.tool === "read" && file) {
        const abs = isAbsolute(file) ? file : resolve(directory, file)
        if (!readMtime.has(sid)) readMtime.set(sid, new Map())
        try { readMtime.get(sid)!.set(rangeKey(abs, input?.args), statSync(abs).mtimeMs) } catch {}
      }

      // Aviso de simbolos borrados: rules §7/§9 lo pedian como checklist
      // MANUAL al final. Un modelo pequeño se lo salta. Aqui es automatico,
      // sincrono y en el mismo turno. Es un AVISO, no un bloqueo: renombrar
      // es legitimo, borrar sin querer no.
      if (input?.tool === "edit" || input?.tool === "write") {
        const isWrite = input.tool === "write"
        const prev = isWrite ? preWrite.get(input.callID) : undefined
        if (isWrite) preWrite.delete(input.callID)
        if (isWrite && prev === undefined) return // fichero nuevo: nada que borrar
        const before = symbols(String(isWrite ? prev : (input?.args?.oldString ?? "")))
        const after = symbols(String(isWrite ? (input?.args?.content ?? "") : (input?.args?.newString ?? "")))
        const gone = [...before].filter((s) => !after.has(s))
        if (gone.length && output) {
          output.output =
            `${output.output ?? ""}\n\n⚠️ GUARD: this edit removed ${gone.length} declaration(s): ${gone.join(", ")}.\n` +
            `If the task was "add" or "fix", put them back before continuing. A green build does not prove you did not delete something.`
        }
      }
    },
  }
}) as any
