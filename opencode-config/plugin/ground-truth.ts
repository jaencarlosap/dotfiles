// ─────────────────────────────────────────────────────────────────────────
// ground-truth — le recuerda al modelo el ESTADO REAL del repo en cada turno.
//
// El problema: tras una compactacion el modelo no sabe que ficheros toco ni
// que datos ya verifico, y vuelve a empezar o se re-inventa cosas. Las reglas
// del prompt le dicen "re-lee el fichero de progreso"... si se acuerda.
// Esto no depende de que se acuerde: se lo ponemos delante cada turno.
//
// DONDE se inyecta importa: al FINAL (ultimo mensaje de usuario), NO en el
// system prompt. El system prompt es el prefijo estable de la peticion; si le
// metes contenido que cambia cada turno, invalidas cualquier reuso de KV cache
// del servidor y pagas el prefill entero otra vez. Al final, el prefijo intacto.
//
// VERIFICADO (v1.18.19, capturando el body real con un proxy):
//   - `experimental.chat.messages.transform` SI llega al wire (texto inyectado
//     presente en la peticion).
//   - `chat.params` funciona para campos conocidos (temperature 0.42 llego),
//     pero `options.reasoning_effort` NO sobreescribe al del agente.
//
// Kill switch:  OPENCODE_GROUND_OFF=1
// ─────────────────────────────────────────────────────────────────────────

import { execFileSync } from "child_process"
import { readFileSync, existsSync } from "fs"
import { join } from "path"

const MAX_LINES = 12
const MAX_CHARS = 1200

// ── La puerta de contexto, SOLO en el primer turno ───────────────────────
//
// Lo que pidio el usuario: "que el modelo se consulte si tiene la informacion
// necesaria; si la tiene, que proceda; si no, que busque en internet hasta
// tener contexto suficiente".
//
// Por que va AQUI y no en `instructions`: una regla en `instructions` viaja
// entera en CADA turno (knowledge-protocol son 1231 tok/turno medidos). Esta
// puerta solo tiene sentido al EMPEZAR: una vez que el modelo ya esta ejecutando
// pasos, repetirsela cada turno es pagar ~120 tokens por vuelta para nada.
// Inyectada en el primer mensaje se paga UNA vez por sesion.
//
// Y por que no solo la skill: la skill hay que abrirla. Esto se lo pone
// delante sin que dependa de que se acuerde — el mismo criterio que el resto
// de este plugin. La skill (`enough-context`) tiene el procedimiento largo.
const GATE = [
  '<context-gate note="injected once, at the start of the task">',
  "Before you write any code, check whether you actually have what this task needs:",
  '1. List the facts it depends on: third-party names and signatures, CLI flags, config keys,',
  '   project layout and conventions, and what "done" means in one sentence.',
  "2. Mark each one KNOWN or UNKNOWN. KNOWN means you can name the source from THIS session:",
  "   a file:line you read, a command output, a URL you fetched, or a VERIFIED FACTS line.",
  '   "I am fairly sure" is UNKNOWN.',
  "3. For every UNKNOWN, ask: would a wrong answer change the code? If no, drop it. If yes,",
  "   resolve it cheapest-first: grep in the repo -> the dependency on disk -> <cmd> --help ->",
  '   a 3-line probe -> docs.sh <pkg> -> web.sh search "<exact identifiers>" + web.sh read <url>.',
  "   You DO have web access from bash. Do not stop one rung short and guess.",
  "4. Six lookups maximum for the whole check, then build. If a fact will not resolve, either",
  "   proceed and STATE the assumption in one line, or stop and ask when being wrong is expensive.",
  "Load the skill `enough-context` for the full procedure.",
  "</context-gate>",
].join("\n")

function sh(cmd: string, args: string[], cwd: string): string {
  try {
    return execFileSync(cmd, args, { cwd, timeout: 1500, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] })
  } catch {
    return ""
  }
}

function clip(s: string, n = MAX_LINES): string[] {
  const lines = s.split("\n").filter((l) => l.trim())
  return lines.length > n ? [...lines.slice(0, n), `… (+${lines.length - n} more)`] : lines
}

// Solo la seccion VERIFIED FACTS del fichero de progreso: es lo que costo
// un lookup y lo que no queremos volver a mirar.
// Las dos convenciones: la actual (`.agent/progress.md`, en un directorio
// gitignored) y la anterior (`.agent_progress.md`). Buscar solo la vieja era un
// BUG: `auto.md` escribe la nueva, asi que los VERIFIED FACTS no se inyectaban
// NUNCA en uso real — justo la mitad mas valiosa de este plugin.
const PROGRESS = [".agent/progress.md", ".agent_progress.md"]

function verifiedFacts(dir: string): string[] {
  const f = PROGRESS.map((p) => join(dir, p)).find((p) => existsSync(p))
  if (!f) return []
  try {
    const body = readFileSync(f, "utf8")
    // Sin regex acrobatica a proposito: `\Z` NO existe en JavaScript (matchea
    // una "Z" literal), asi que la version anterior solo encontraba la seccion
    // cuando venia OTRA cabecera detras. Si `# VERIFIED FACTS` era la ultima
    // del fichero — el caso normal — devolvia vacio en silencio.
    const lines = body.split(/\r?\n/)
    const start = lines.findIndex((l) => /^#+[ \t]*VERIFIED FACTS[ \t]*$/i.test(l))
    if (start === -1) return []
    const rest = lines.slice(start + 1)
    const end = rest.findIndex((l) => /^#/.test(l))
    return clip((end === -1 ? rest : rest.slice(0, end)).join("\n"))
  } catch {
    return []
  }
}

export default (async ({ directory }: any) => {
  return {
    "experimental.chat.messages.transform": async (_input: any, output: any) => {
      if (process.env.OPENCODE_GROUND_OFF === "1") return
      const msgs = output?.messages
      if (!Array.isArray(msgs) || msgs.length === 0) return

      // Primer turno = todavia no ha hablado el asistente. Se comprueba por el
      // rol y, si esta build no lo expone, por longitud (1 mensaje = el del
      // usuario). Ante la duda, NO se inyecta: mejor perder la puerta que
      // repetirla cada vuelta.
      const roleOf = (m: any) => m?.role ?? m?.info?.role
      const roles = msgs.map(roleOf).filter(Boolean)
      const firstTurn = roles.length ? !roles.includes("assistant") : msgs.length === 1

      const dirty = clip(sh("git", ["status", "--short"], directory))
      const facts = verifiedFacts(directory)
      if (!dirty.length && !facts.length && !firstTurn) return // nada util que decir: no gastes tokens

      let block = ""
      if (dirty.length || facts.length) {
        block += "\n\n<repo-state note=\"injected automatically, always current\">"
        if (dirty.length) block += `\nuncommitted changes (git status --short):\n${dirty.join("\n")}`
        else block += "\nworking tree is clean"
        if (facts.length) block += `\n\nfacts you already verified (do not look these up again):\n${facts.join("\n")}`
        block += "\n</repo-state>"
        if (block.length > MAX_CHARS) block = block.slice(0, MAX_CHARS) + "\n…</repo-state>"
      }
      // La puerta va DESPUES del estado: lo ultimo que lee es lo que tiene que
      // hacer primero.
      if (firstTurn && process.env.OPENCODE_GATE_OFF !== "1") block += "\n\n" + GATE
      if (!block) return

      // Al ULTIMO mensaje, para no tocar el prefijo estable de la peticion.
      const last = msgs[msgs.length - 1]
      const part = (last?.parts ?? []).find((p: any) => p?.type === "text" && typeof p.text === "string")
      if (part) part.text += block
    },
  }
}) as any
