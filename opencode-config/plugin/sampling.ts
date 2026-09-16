// ─────────────────────────────────────────────────────────────────────────
// sampling — temperature/top_p SOLO para los modelos locales, no en el agente.
//
// Por que existe: `agent/auto.md` llevaba `temperature: 0.6` y `top_p: 0.95`
// (los valores de la model card de Qwen para thinking mode). El frontmatter se
// aplica a CUALQUIER modelo con el que se use el agente, y al cambiar en la TUI
// a un GPT de razonamiento la peticion entera fallaba:
//
//   Unsupported parameter: 'top_p' is not supported with this model.
//
// (Los GPT-5.x rechazan `top_p`, y varios tambien `temperature`.) Un agente
// que solo funciona con un modelo no es "auto". Asi que el sampling sale del
// agente y entra aqui, condicionado al PROVIDER: para `local` (llama-swap +
// llama.cpp, Qwen) se ponen los valores de siempre; para todo lo demas no se
// toca nada y la API usa sus defaults.
//
// VERIFICADO (README, "chat.params"): el hook llega al wire para temperature.
// `topP` es campo conocido del mismo output. Los valores siguen sin estar
// medidos para qwen-35b (era "PENDING" en auto.md y lo sigue siendo).
//
// Kill switch:  OPENCODE_SAMPLING_OFF=1
// ─────────────────────────────────────────────────────────────────────────

// Providers cuyo backend es llama.cpp y acepta estos parametros.
const LOCAL = new Set(["local"])

// Por agente: los valores que antes vivian en su frontmatter.
const PARAMS: Record<string, { temperature: number; topP: number }> = {
  auto: { temperature: 0.6, topP: 0.95 },
}

export default (async () => {
  return {
    "chat.params": async (input: any, output: any) => {
      if (process.env.OPENCODE_SAMPLING_OFF === "1") return
      const provider = String(input?.model?.providerID ?? input?.provider?.id ?? input?.provider?.info?.id ?? "")
      if (!LOCAL.has(provider)) return
      const p = PARAMS[String(input?.agent ?? "")]
      if (!p) return
      output.temperature = p.temperature
      output.topP = p.topP
    },
  }
}) as any
