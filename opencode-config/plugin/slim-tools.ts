// ─────────────────────────────────────────────────────────────────────────
// slim-tools — recorta la descripcion de las herramientas mas gordas.
//
// Por que: los esquemas de herramientas son el 39% del prompt FIJO. Medido
// contra el server (usage.prompt_tokens real), con la config de ayer:
//
//   prompt fijo actual .................. 9517 tok
//   sin NINGUNA herramienta ............. 5744 tok
//   => los esquemas cuestan ............. 3773 tok  (39%)
//
// Y estaba muy mal repartido: la descripcion de `bash` sola son 4671 CHARS,
// mas que las de edit+read+grep+glob+write+skill juntas. Se paga en cada
// turno del bucle agentico, y ademas se re-procesa en cada prefill: no es
// solo contexto, es latencia.
//
// Que NO se hace aqui: truncar a lo bruto. Cortar a 200 chars ahorraba 2829
// tok pero se lleva por delante reglas que importan (usar `workdir` en vez de
// `cd`, que la salida larga se guarda en fichero, no commitear sin permiso).
// Lo de abajo es una reescritura a mano que CONSERVA todas esas reglas.
//
// Kill switch:  OPENCODE_SLIM_OFF=1
// ─────────────────────────────────────────────────────────────────────────

import { readFileSync } from "fs"

// Marca que un agente pone en SU PROPIO prompt para declarar "yo no programo".
// Quien la lleve se queda sin las reglas de ingenieria (que son de codigo).
const NON_CODING = /NON-CODING AGENT: skip engineering rules/

// Se borra el contenido LITERAL de estos ficheros, no un patron.
const RULE_FILES = [
  `${process.env.HOME}/.config/opencode/rules/engineering-discipline.md`,
  `${process.env.HOME}/.config/opencode/rules/knowledge-protocol.md`,
]

// El original mete datos del entorno (SO, shell, directorio temporal
// pre-aprobado). Se extraen del texto real en vez de hardcodearlos, para que
// esto siga siendo cierto si opencode los cambia.
function compactBash(orig: string): string {
  const env = orig.match(/Be aware: (OS: [^\n]+)/)?.[1] ?? ""
  const tmp = orig.match(/Use `([^`]+)` for temporary work/)?.[1]
  const limits = orig.match(/exceeds (\d+) lines or (\d+) bytes/)
  const lines = limits?.[1] ?? "400"
  const bytes = limits?.[2] ?? "16000"

  return [
    "Run a shell command in a persistent shell session.",
    env && `Environment: ${env}.`,
    "For terminal work (git, npm, docker, go, make) — NOT for file operations:",
    "use glob to find files, grep to search content, read to read, edit to change,",
    "write to create. Do not use find/grep/cat/head/tail/sed/awk/echo for those.",
    "",
    `- Use the workdir parameter to run somewhere else. Do NOT use "cd X && ...".`,
    `- Quote paths containing spaces: rm "path with spaces/file.txt".`,
    "- Optional timeout in ms; default 120000.",
    `- Output over ${lines} lines or ${bytes} bytes is truncated and written to a file;`,
    "  read it with read (offset/limit) or grep. Do NOT pipe through head/tail.",
    "- Chain dependent commands with && in one call; independent ones as separate",
    "  calls. Never separate commands with newlines.",
    tmp && `- Temporary work outside the workspace goes in ${tmp} (already approved).`,
    "",
    "Git: only commit, push or open PRs when explicitly asked. Before committing,",
    "check git status/diff, stage only what you intend, never commit secrets. Do not",
    "force-push, amend, skip hooks or change git config unless asked. Use gh for",
    "GitHub work and return the PR URL.",
  ]
    .filter(Boolean)
    .join("\n")
}

export default (async () => {
  return {
    // ── PATH: que `docs.sh` se pueda llamar por su nombre ──────────────────
    // Las reglas decian `~/.config/opencode/bin/docs.sh ...`. En el benchmark
    // el modelo intento LEER esa ruta con la herramienta `read` en vez de
    // ejecutarla — y como cae fuera del proyecto, salta el permiso
    // `external_directory`, que en modo no interactivo se auto-rechaza. Turno
    // perdido (medido: 1 de los 4 runs).
    //
    // Metiendo el bin en el PATH, la regla pasa a ser `docs.sh npm express`:
    // sin rutas absolutas, mas corta, y sin nada que invite a abrir un fichero
    // fuera del proyecto.
    "shell.env": async (_input: any, output: any) => {
      const bin = `${process.env.HOME}/.config/opencode/bin`
      const cur = output?.env?.PATH ?? process.env.PATH ?? ""
      if (output?.env && !cur.split(":").includes(bin)) output.env.PATH = `${bin}:${cur}`
    },

    // ── Reglas de CODIGO fuera de los agentes que no programan ────────────
    // `instructions` en opencode.jsonc es GLOBAL y no se puede desactivar por
    // agente: el schema de AgentConfig no tiene campo `instructions`
    // (verificado contra https://opencode.ai/config.json).
    //
    // Medido en el agente `ticket`: de sus 5558 tokens de prompt fijo, 3070
    // (el 55%) eran engineering-discipline + knowledge-protocol — "grep antes
    // de escribir", la escalera de lookups... para un agente que redacta
    // Historias de Usuario y no toca codigo.
    //
    // ⚠️ COMO **NO** HACER ESTO. La primera version borraba por regex
    // (`/^#\s*(Engineering discipline|Knowledge protocol)/m`) sobre cada
    // entrada de `output.system`. Falla, y en grande: opencode manda el system
    // prompt COMPLETO en UNA sola string (17.206 chars: prompt del agente +
    // reglas + skills). Con la flag `m` el patron casaba dentro de esa string
    // combinada y se blanqueaba ENTERA -> el agente se quedaba con 0 chars de
    // system y se inventaba el formato del ticket de cero. Verificado en el
    // trafico real: `system: 1 mensaje, 0 chars`.
    //
    // El test unitario NO lo detecto porque su fixture era un array de strings
    // separadas — una forma que no existe en la practica. Ahora el test usa la
    // string combinada real.
    //
    // La version buena no adivina limites: lee los ficheros de reglas de disco
    // y borra su contenido LITERAL. Si no aparece tal cual, no toca nada.
    "experimental.chat.system.transform": async (_input: any, output: any) => {
      if (process.env.OPENCODE_SLIM_OFF === "1") return
      const sys: string[] = output?.system
      if (!Array.isArray(sys) || !sys.length) return
      if (!sys.some((p) => typeof p === "string" && NON_CODING.test(p))) return

      const rules = RULE_FILES.map((f) => {
        try { return readFileSync(f, "utf8").trim() } catch { return "" }
      }).filter((r) => r.length > 100)
      if (!rules.length) return

      for (let i = 0; i < sys.length; i++) {
        const orig = sys[i]
        if (typeof orig !== "string" || !orig) continue
        let out = orig
        for (const r of rules) out = out.split(r).join("")
        // Red de seguridad: si el recorte se lleva casi todo, algo va mal —
        // deja la entrada como estaba. Es exactamente el fallo de la v1.
        if (out.trim().length < 200 && orig.trim().length >= 200) continue
        sys[i] = out
      }
    },

    "tool.definition": async (input: any, output: any) => {
      if (process.env.OPENCODE_SLIM_OFF === "1") return
      if (input?.toolID !== "bash") return
      const orig = String(output?.description ?? "")
      // Si opencode cambia el texto y ya es corto, no toques nada.
      if (orig.length < 1500) return
      output.description = compactBash(orig)
    },
  }
}) as any
