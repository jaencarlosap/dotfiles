// ─────────────────────────────────────────────────────────────────────────
// ticket-format — arregla la numeracion de las secciones del ticket de Jira.
//
// El modelo escribe bien las 6 secciones pero se equivoca al NUMERARLAS: en
// varias pruebas puso `h3. 5.` dos veces, dejando la Documentacion como 5 en
// vez de 6. Se intento arreglar por prompt (una lista de auto-repaso con los
// errores reales) y NO se corrigio: es un fallo mecanico, de los que un modelo
// pequeño no ve al releerse.
//
// Numerar 1..6 en orden es una invariante, no una opinion. Asi que se hace
// aqui, deterministicamente y a coste cero, en vez de gastar mas tokens de
// prompt pidiendoselo. Mismo principio que `anti-slop-guard`: lo que se pueda
// imponer, no se pide.
//
// MUY IMPORTANTE: este hook ve la salida de TODOS los agentes, asi que solo
// toca texto que es inequivocamente un ticket (tiene `h3. Titulo:` y al menos
// tres cabeceras `h3. N.`). Cualquier otra cosa se devuelve intacta.
//
// Kill switch:  OPENCODE_TICKETFMT_OFF=1
// ─────────────────────────────────────────────────────────────────────────

const SECTION = /^h3\. \d+\.\s/gm

// Devuelve el texto renumerado, o null si no hay nada que hacer (o si esto no
// es un ticket). Un solo sitio para la regla, porque ahora se aplica en DOS
// caminos distintos: el texto que va al chat y el fichero que se escribe.
//
// NO exportar: opencode trata cualquier named export de un plugin como una
// factory y lo invoca con su PluginInput — exportar un helper tumba el modulo
// entero en el arranque (paso de verdad con anti-slop-guard).
function renumber(text: unknown): string | null {
  if (typeof text !== "string" || !text.includes("h3. Titulo:")) return null
  const matches = text.match(SECTION)
  if (!matches || matches.length < 3) return null
  let n = 0
  const fixed = text.replace(SECTION, () => `h3. ${++n}. `)
  return fixed === text ? null : fixed
}

export default (async () => {
  return {
    "experimental.text.complete": async (_input: any, output: any) => {
      if (process.env.OPENCODE_TICKETFMT_OFF === "1") return
      const fixed = renumber(output?.text)
      if (fixed) output.text = fixed
    },

    // El ticket ya no vive solo en el chat: la skill `jira-ticket` lo escribe en
    // `ticket-<algo>.md` para que el usuario lo lea y lo confirme. Sin esto, el
    // renumerado se aplicaba al texto del chat y el FICHERO —que es el que se
    // lee y el que acaba en Jira— se quedaba con el `h3. 5.` duplicado.
    //
    // `write` lleva el contenido entero, asi que se puede renumerar entero.
    // `edit` solo si su `newString` es el ticket COMPLETO (lleva `h3. Titulo:`):
    // renumerar un fragmento desde 1 convertiria la seccion 5 en la 1.
    "tool.execute.before": async (input: any, output: any) => {
      if (process.env.OPENCODE_TICKETFMT_OFF === "1") return
      const args = output?.args
      if (!args) return
      if (input?.tool === "write") {
        const fixed = renumber(args.content)
        if (fixed) args.content = fixed
      } else if (input?.tool === "edit") {
        const fixed = renumber(args.newString)
        if (fixed) args.newString = fixed
      }
    },
  }
}) as any
