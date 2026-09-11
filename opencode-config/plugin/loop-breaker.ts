// ─────────────────────────────────────────────────────────────────────────
// loop-breaker — corta el bucle cuando el modelo repite algo que YA fallo.
//
// El prompt de `auto` ya lo prohibe (§5.4 "Never run the same failing command a third
// time"). No sirve: el modelo lo incumple.
// Es el mismo patron que el resto de este directorio — una regla del prompt se
// cumple "casi siempre", un hook se cumple SIEMPRE — y aqui es peor que en
// otros sitios, porque el fallo no es un fichero de mas: es la sesion entera
// girando en redondo hasta que alguien la mata.
//
// Casos REALES medidos con qwen3.5-9b-mtp (log de opencode, no anecdotas):
//   - `webfetch "<url>" 2>/dev/null | grep ...`  ->  **229 pasos** identicos.
//   - `ripgrep --help 2>&1 | grep -i max` / `| grep -i limit`, alternandose.
//
// LA CLAVE DEL DISEÑO: no se bloquea "repetir", se bloquea **repetir sin
// informacion nueva**. Un comando que se repite y devuelve algo DISTINTO no es
// un bucle (`docker compose ps` esperando a que un servicio levante, `npm test`
// tras editar). Lo que no puede seguir es repetir cuando la salida es IDENTICA:
// ahi el tercer intento ya sabemos como acaba.
//
// Dos claves por comando, porque el bucle real muto la tuberia sin cambiar el
// comando de verdad:
//   exacta : el comando entero normalizado.
//   cabeza : lo que hay ANTES del primer `|`. Asi `X | grep max` y
//            `X | grep limit` cuentan como el mismo intento, que es lo que son.
//
// Kill switch:  OPENCODE_LOOP_OFF=1
// ─────────────────────────────────────────────────────────────────────────

import { createHash } from "crypto"

const MAX_TRACKED = 200 // por sesion; evita crecer sin limite en sesiones largas

type Rec = { runs: number; lastHash: string; repeats: number; blocks: number; attempts: number }

// ── Por que esto no puede mirar solo `bash` ──────────────────────────────
// Caso real: al pedirle crear el ticket en Jira con el MCP caido, el modelo
// llamo a `jiraAdmin_jira-ticket-create` **201 veces** en un solo run. El
// loop-breaker no lo vio por dos motivos, y los dos habia que arreglarlos:
//
//   1) Solo miraba `bash`. Una tool de MCP no es bash.
//   2) La regla era "misma salida IDENTICA dos veces", y cuando una tool
//      FALLA puede no llegar a `tool.execute.after` — sin salida registrada,
//      `repeats` nunca subia y el bucle era invisible.
//
// Por eso ahora se cuentan INTENTOS en el `before`: tres llamadas identicas a
// la misma herramienta con los mismos argumentos y sin que nada haya cambiado
// en disco son un bucle, tanto si devuelven algo como si revientan.
const ATTEMPT_LIMIT = 3

// Bloquear no basta si el modelo no lee el bloqueo. MEDIDO sobre la base de
// datos de sesiones (156 sesiones, 34k parts): en la sesion "Crear proyecto
// Node con script de hora" el modelo se comio el MISMO bloqueo **85 veces**
// seguidas con `cat /tmp/clock-app/print-time.js`. O sea: el loop-breaker
// convirtio un bucle infinito en un bucle infinito BLOQUEADO.
//
// Hipotesis del porque: el mensaje largo, identico turno tras turno, se vuelve
// invisible. Asi que a partir del tercer bloqueo el mensaje CAMBIA y se hace
// corto e imperativo. Y si lo que intenta es leer un fichero por bash, se le
// da la alternativa que SI funciona: la herramienta `read`.
const FILE_READ = /^\s*(cat|head|tail|less|more|bat)\s+(-\S+\s+)*([^\s|&;<>]+)\s*$/

function escalated(cmd: string, blocks: number): string {
  const path = cmd.match(FILE_READ)?.[3]
  return (
    `STOP. This command has been blocked ${blocks} times. It will NEVER run again in this session. ` +
    `Trying it once more is the definition of the loop you are in.\n` +
    (path
      ? `To read that file use the \`read\` tool with filePath "${path}" — a different tool, not bash. `
      : `Use a DIFFERENT tool or a different mechanism. `) +
    `If you already have what you need, answer the user now. If you do not, say exactly what is ` +
    `missing and stop. Do not run another command until you have written one sentence explaining ` +
    `what changed in your approach.`
  )
}

const norm = (s: string) => s.trim().replace(/\s+/g, " ")
const hash = (s: string) => createHash("sha1").update(s).digest("hex").slice(0, 16)

// Lo que hay antes del primer `|` REAL (fuera de comillas). Lo de "fuera de
// comillas" no es un detalle: `grep -E "HTTP|status|ok"` no tiene ninguna
// tuberia, y partirlo por ese `|` genera una clave falsa. El guard hermano
// (anti-slop-guard) llego a BLOQUEAR un comando por ese mismo bug.
function headOf(cmd: string): string {
  let quote: '"' | "'" | null = null
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i]
    if (quote) { if (c === quote && cmd[i - 1] !== "\\") quote = null; continue }
    if (c === '"' || c === "'") { quote = c; continue }
    if (c === "|") return norm(cmd.slice(0, i))
  }
  return norm(cmd)
}

function keysFor(cmd: string): string[] {
  const exact = norm(cmd)
  const head = headOf(cmd)
  return head && head !== exact ? [exact, "head:" + head] : [exact]
}

// Para cualquier herramienta que no sea bash: nombre + argumentos. Los
// argumentos se serializan con las claves ordenadas para que dos llamadas
// equivalentes no parezcan distintas por el orden del JSON.
function toolKey(tool: string, args: any): string {
  let a = ""
  try {
    a = JSON.stringify(args, Object.keys(args ?? {}).sort())
  } catch {
    a = String(args)
  }
  return `${tool}:${norm(a).slice(0, 400)}`
}

// ── Segunda regla: girar en redondo sin repetirse ────────────────────────
// Un bucle no siempre repite el MISMO comando. Caso real (crear un proyecto de
// Node): el proyecto estaba hecho y funcionando en el paso ~20, y el modelo
// gasto los 100 pasos siguientes en "verificar" — grep TODO, grep comentarios,
// ls, git status, grep otra vez — variando lo justo para que ninguna clave
// coincidiera. Termino agotando `steps: 120` sin cerrar la tarea.
//
// Aqui NO se bloquea: bloquear un analisis legitimo (que es todo lectura) seria
// peor que el problema. Se AÑADE una linea al final de la salida de la
// herramienta, que es la unica forma de hablarle al modelo sin abortarle el
// turno. Cada NUDGE_EVERY comandos sin tocar un fichero.
const NUDGE_AT = 15
const NUDGE_EVERY = 10
const nudge = (n: number) =>
  `\n\n[loop-breaker] ${n} commands since your last file change. Verification is not ` +
  `progress. Decide now: if the goal is already met, say so and finish; if it is not, make ` +
  `the next change; if you are stuck on an error, load the \`unstick\` skill. Do not run ` +
  `another inspection command without saying what it is for.`

export default (async () => {
  // sessionID -> key -> Rec
  const state = new Map<string, Map<string, Rec>>()
  // sessionID -> comandos bash desde el ultimo edit/write
  const sinceChange = new Map<string, number>()
  const forSession = (sid: string) => {
    let m = state.get(sid)
    if (!m) state.set(sid, (m = new Map()))
    return m
  }

  // Un edit/write es informacion nueva: el mundo cambio, repetir el comando ya
  // no es repetir. Se limpia el historial de esa sesion.
  const reset = (sid: string) => {
    state.get(sid)?.clear()
    sinceChange.set(sid, 0)
  }

  return {
    "tool.execute.before": async (input: any, output: any) => {
      if (process.env.OPENCODE_LOOP_OFF === "1") return
      const tool = String(input?.tool ?? "")
      if (!tool) return
      const m = forSession(String(input?.sessionID ?? "-"))

      // ── Cualquier herramienta que NO sea bash: se cuentan intentos ────────
      // `skill` queda fuera a proposito: cargar dos veces la misma skill es
      // ruido, no un bucle, y bloquearlo deja al modelo sin su procedimiento.
      if (tool !== "bash") {
        if (tool === "skill" || tool === "todowrite" || tool === "question") return
        const k = toolKey(tool, output?.args)
        const r = m.get(k) ?? { runs: 0, lastHash: "", repeats: -1, blocks: 0, attempts: 0 }
        r.attempts += 1
        m.set(k, r)
        if (r.attempts > ATTEMPT_LIMIT) {
          r.blocks += 1
          throw new Error(
            `BLOCKED (loop): you have called \`${tool}\` with these exact arguments ` +
              `${r.attempts} times in this session. It is not going to behave differently on ` +
              `attempt ${r.attempts + 1}.\n` +
              `If it kept failing, the cause is the tool or its input — not the number of tries. ` +
              `Report the LAST error you got, verbatim and in one line, and say what you could not ` +
              `do because of it. If the work has a fallback that does not need this tool (a file ` +
              `already written, a manual step for the user), say so and stop there.\n` +
              `Do NOT invent a result this tool never returned.`,
          )
        }
        return
      }

      const cmd = String(output?.args?.command ?? "")
      if (!cmd.trim()) return

      for (const k of keysFor(cmd)) {
        const r = m.get(k)
        // `repeats >= 1` = ya se ejecuto dos veces con salida IDENTICA.
        if (r && r.repeats >= 1) {
          r.blocks = (r.blocks ?? 0) + 1
          // Tercer bloqueo del mismo comando: el mensaje largo no esta calando.
          if (r.blocks >= 3) throw new Error(escalated(cmd, r.blocks))
          const what = k.startsWith("head:")
            ? "the same command with a different filter after the pipe"
            : "this exact command"
          throw new Error(
            `BLOCKED (loop): you already ran ${what} ${r.runs} times and the output was ` +
              `IDENTICAL every time. Running it again gives the same output. Changing the ` +
              `\`grep\`/\`head\` after the pipe is NOT a different attempt.\n` +
              `Do this instead, in order:\n` +
              `1. Run it ONCE with no filters — no \`| grep\`, no \`| head\`, no \`2>/dev/null\` — ` +
              `and read the FULL output. An error you filtered out looks exactly like an empty result.\n` +
              `2. Write the error's meaning in one sentence. "command not found" = it does not exist ` +
              `here; "No such file" = wrong path; "Cannot find module" = not installed.\n` +
              `3. If you cannot explain it from the output, look it up:\n` +
              `   web.sh search "<paste the exact error line>"\n` +
              `4. Load the skill \`unstick\` for the full procedure.\n` +
              `Then change the APPROACH. A different flag on the same broken command is not a ` +
              `different approach. If nothing is left to try, stop and report the exact error.`,
          )
        }
      }
    },

    "tool.execute.after": async (input: any, output: any) => {
      if (process.env.OPENCODE_LOOP_OFF === "1") return
      const sid = String(input?.sessionID ?? "-")

      // Cambiar ficheros invalida el historial: el siguiente intento SI es nuevo.
      if (input?.tool === "edit" || input?.tool === "write" || input?.tool === "patch") {
        reset(sid)
        return
      }
      if (input?.tool !== "bash") return

      const cmd = String(input?.args?.command ?? "")
      if (!cmd.trim()) return
      const raw = output?.output ?? output?.metadata?.output ?? output ?? ""
      const h = hash(norm(typeof raw === "string" ? raw : JSON.stringify(raw)))

      const n = (sinceChange.get(sid) ?? 0) + 1
      sinceChange.set(sid, n)
      if (n >= NUDGE_AT && (n - NUDGE_AT) % NUDGE_EVERY === 0 && typeof output?.output === "string")
        output.output += nudge(n)

      const m = forSession(sid)
      if (m.size > MAX_TRACKED) m.clear()
      for (const k of keysFor(cmd)) {
        const r = m.get(k) ?? { runs: 0, lastHash: "", repeats: -1, blocks: 0, attempts: 0 }
        r.repeats = r.runs > 0 && r.lastHash === h ? r.repeats + 1 : 0
        r.runs += 1
        r.lastHash = h
        m.set(k, r)
      }
    },

    // Sesion terminada: soltar su historial.
    event: async ({ event }: any) => {
      if (event?.type === "session.deleted" || event?.type === "session.idle") {
        const sid = event?.properties?.sessionID ?? event?.properties?.info?.id
        if (sid) { state.delete(String(sid)); sinceChange.delete(String(sid)) }
      }
    },
  }
}) as any
