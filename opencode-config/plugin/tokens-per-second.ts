// ─────────────────────────────────────────────────────────────────────────
// tokens-per-second — toast con la velocidad de generacion tras cada respuesta.
// Uso principal: vigilar el server local (LM Studio). Si el throughput cae de
// golpe (p.ej. de ~50 a ~15), casi siempre es que el KV cache se salio de la
// VRAM y hay offload a CPU (ver README -> settings de carga de LM Studio).
//
// HONESTIDAD sobre lo que mide (importante): opencode solo expone timing a
// nivel de MENSAJE (info.time.created -> completed). Ese lapso incluye el
// time-to-first-token Y el tiempo de ejecucion de herramientas (un `docker
// build` de 60s cuenta como si el modelo hubiera ido lento). NO es la velocidad
// de decode pura. Por eso:
//   - lo etiquetamos "throughput del turno", no "decode tok/s";
//   - saltamos turnos triviales (<40 tokens), donde el TTFT domina y el numero
//     enganaria;
//   - para la velocidad de decode EXACTA usa `make bench` en opencode-config.
// Aun asi, sobre una carga parecida, la tendencia delata el offload a CPU.
//
// Datos (verificado en el SDK v1 de opencode 1.18.4):
//   evento message.updated -> event.properties.info (AssistantMessage)
//     info.role, info.time{created,completed}, info.tokens{output,reasoning,...}
//   toast: client.tui.showToast({ body:{ message, variant, duration } })
//
// Nota util: los tokens de reasoning (thinking) cuentan como generados, asi el
// toast tambien te deja VER el coste del thinking (el agente `analyze` mostrara
// 🧠 con muchos; `auto`, sin thinking, ninguno).
//
// ── DESACTIVADO POR DEFECTO ──────────────────────────────────────────────
// El plugin se conserva pero NO hace nada salvo que lo actives explicitamente.
// Para encenderlo:  exporta  OPENCODE_TPS_ON=1  antes de abrir opencode
//   (p.ej. en tu shell:  OPENCODE_TPS_ON=1 opencode   ó ponlo en el rc).
// Se dejo apagado porque el toast es transitorio; ver README para la via de
// una ubicacion PERSISTENTE (paquete npm de plugin TUI, seccion "opción B").
// ─────────────────────────────────────────────────────────────────────────

import type { Plugin } from "@opencode-ai/plugin"

const ENABLED = process.env.OPENCODE_TPS_ON === "1" // opt-in: apagado por defecto
const MIN_TOKENS = 40         // por debajo, el TTFT domina -> numero no fiable
const TOAST_MS = 8000         // duracion del toast (ms); 8s para poder leerlo
const reported = new Set<string>() // dedupe: message.updated se emite N veces
let announced = false         // toast de arranque una sola vez por proceso

export default (async ({ client }) => {
  return {
    event: async ({ event }: { event: any }) => {
      try {
        if (!ENABLED) return

        // Fire-and-forget: NUNCA await al toast. En modo headless (opencode run)
        // no hay TUI que responda al POST y un await bloquearia el turno entero.
        const toast = (message: string, variant: string, duration: number) => {
          try { Promise.resolve(client.tui.showToast({ body: { message, variant, duration } })).catch(() => {}) } catch {}
        }

        // Aviso de arranque: los plugins de hook NO salen en el panel "Plugins"
        // de la TUI, asi que este toast confirma que las metricas estan vivas.
        if (!announced) {
          announced = true
          toast("⚡ métricas tok/s activas", "info", 3000)
        }

        if (event?.type !== "message.updated") return

        const info = event.properties?.info
        if (!info || info.role !== "assistant") return
        if (!info.time?.completed || !info.time?.created) return // aun generando
        if (reported.has(info.id)) return

        const t = info.tokens || {}
        const input = Number(t.input || 0)
        const output = Number(t.output || 0)
        const reasoning = Number(t.reasoning || 0)
        const generated = output + reasoning
        const secs = (info.time.completed - info.time.created) / 1000
        if (generated < MIN_TOKENS || secs <= 0) return // turno trivial: no molestar

        reported.add(info.id)
        if (reported.size > 500) reported.clear()

        const tps = generated / secs
        const nf = (n: number) => n.toLocaleString()
        const think = reasoning > 0 ? ` · 🧠${nf(reasoning)}` : ""
        // tokens del mensaje (entrada→salida) + velocidad + duracion
        const msg = `⚡ ${tps.toFixed(1)} tok/s · ${nf(input)}→${nf(output)} tok${think} · ${secs.toFixed(1)}s`

        // Solo marcamos "lento" cuando es claramente anomalo (offload a CPU);
        // no alarmamos por turnos con TTFT/herramientas, que bajan el numero.
        const variant = tps >= 25 ? "success" : tps >= 8 ? "info" : "warning"

        toast(msg, variant, TOAST_MS)
      } catch {
        // nunca romper la sesion por el plugin de metricas
      }
    },
  }
}) satisfies Plugin
