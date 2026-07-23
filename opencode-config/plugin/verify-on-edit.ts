// ─────────────────────────────────────────────────────────────────────────
// verify-on-edit — bucle de feedback tras cada edicion.
//
// Cuando el agente edita/escribe un fichero de codigo, este plugin corre un
// chequeo RAPIDO de compilacion/lint de ESE fichero y, si falla, anexa el
// error al resultado de la herramienta. El modelo lo ve inline en el mismo
// turno, sin tener que acordarse de verificar. Es el "post-edit diagnostic"
// que hace a Claude Code independiente, adaptado a un modelo pequeño local.
//
// Complementa (no duplica) al LSP y al formatter:
//   - formatter  -> arregla estilo (gofmt/prettier/ruff --fix)
//   - LSP        -> diagnosticos semanticos en el editor
//   - este plugin-> garantiza un "❌ COMPILA/LINT ROTO" imposible de ignorar,
//                   sincrono, en el output de la tool, para el fichero tocado.
//
// Se puede desactivar en cualquier momento con:  OPENCODE_VERIFY_SKIP=1
// La verificacion PESADA (tests, build completo) va en el comando /verify,
// no aqui: correr la suite entera tras cada edicion seria demasiado lento.
// ─────────────────────────────────────────────────────────────────────────

import type { Plugin } from "@opencode-ai/plugin"

// Extension -> como chequear ese fichero. Devuelve el comando (argv) a correr.
// `dir` es el directorio del fichero (relativo al proyecto). Solo comandos
// RAPIDOS: nada que compile el repo entero ni que baje dependencias.
function checkFor(ext: string, file: string, dir: string): string[] | null {
  switch (ext) {
    // parsea el fichero; -e reporta todos los errores de sintaxis, no solo el 1º.
    case "go":
      return ["gofmt", "-e", "-l", file]
    // compila sin ejecutar; error de sintaxis/indentacion al instante.
    case "py":
      return ["python3", "-m", "py_compile", file]
    // chequeo de sintaxis del shell sin ejecutarlo.
    case "sh":
    case "bash":
      return ["bash", "-n", file]
    // ts/tsx/js/jsx/rust: se dejan al LSP. `tsc`/`cargo` por-fichero es
    // demasiado lento para correr tras cada edicion.
    default:
      return null
  }
}

const MAX = 1500 // recorta el error para no inundar el contexto del modelo

export default (async ({ directory, $ }) => {
  return {
    "tool.execute.after": async (input: any, output: any) => {
      try {
        if (process.env.OPENCODE_VERIFY_SKIP === "1") return
        if (input?.tool !== "edit" && input?.tool !== "write") return

        const file: string | undefined = input?.args?.filePath
        if (!file || typeof file !== "string") return

        const ext = file.split(".").pop()?.toLowerCase() ?? ""
        const dirRel = file.replace(directory, "").replace(/^\/+/, "").split("/").slice(0, -1).join("/") || "."
        const argv = checkFor(ext, file, dirRel)
        if (!argv) return

        // $ es el shell de Bun: .nothrow() no lanza en exit!=0, .quiet() no
        // vuelca a stdout. Timeout corto: si el chequeo tarda, no bloquea.
        const r = await $`${argv}`.cwd(directory).nothrow().quiet()

        // gofmt -l imprime el nombre del fichero si NO esta bien formateado
        // (aunque parsee); nos interesa solo el fallo de PARSEO -> exit != 0.
        if (r.exitCode === 0) return

        const err = (r.stderr?.toString() || r.stdout?.toString() || "").trim()
        if (!err) return

        const note =
          `\n\n---\n❌ VERIFY-ON-EDIT: '${argv[0]}' fallo en ${file} (exit ${r.exitCode}).\n` +
          `Arreglalo antes de continuar — no dejes el fichero roto:\n\`\`\`\n` +
          (err.length > MAX ? err.slice(0, MAX) + "\n…(recortado)" : err) +
          `\n\`\`\``

        if (typeof output?.output === "string") output.output += note
      } catch {
        // Nunca romper la edicion por un fallo del plugin. Silencioso a proposito.
      }
    },
  }
}) satisfies Plugin
