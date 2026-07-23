# opencode-config

Configuración de [opencode](https://opencode.ai) versionada con git, apuntando a
un servidor local de modelos (**LM Studio** en `pcgamer`, vía Tailscale, 12GB VRAM).

El repo es la **fuente de verdad**. `make install` reemplaza los archivos en
`~/.config/opencode` por *symlinks* hacia este repo.

## Uso

```bash
make install       # crea los symlinks (respalda lo previo)
make status        # ver estado de los symlinks
make test-conn     # ping a LM Studio en pcgamer
make models        # lista modelos disponibles
make ctx           # contexto real del server vs. lo declarado + umbral
make bench         # tokens/seg del modelo cargado
make init-agents   # genera AGENTS.md en el proyecto actual (DIR=... o CWD)
make uninstall     # quita los symlinks
make restore       # restaura el ultimo respaldo
```

## Qué se versiona

| Archivo / carpeta        | Rol                                                        |
| ------------------------ | ---------------------------------------------------------- |
| `opencode.jsonc`         | Config principal: provider, modelos, permisos, LSP/formatter |
| `agent/auto.md`          | Agente primario de coding (Qwen3.5 9B)                     |
| `agent/analyze.md`       | Agente de análisis/arquitectura (delegable con `task`)     |
| `rules/*.md`             | Reglas anti-slop inyectadas en **todos** los agentes       |
| `command/*.md`           | Comandos: `/verify`, `/fix`, `/pr`                         |
| `plugin/verify-on-edit.ts` | Chequeo de compilación/lint tras cada edición            |
| `templates/AGENTS.md`    | Plantilla de contexto por-proyecto (`make init-agents`)    |
| `bin/init-agents.sh`     | Genera un `AGENTS.md` con los comandos ya detectados       |

## 🧹 Anti-slop: ficheros de más, duplicados y "empezar de cero"

Síntomas típicos del modelo local: crea ficheros que nadie pidió, escribe una
segunda versión de algo que ya existe, deja `TODO`/stubs, y a mitad de tarea
larga vuelve a escribir desde cero un fichero que él mismo había creado.

Las tres causas y su arreglo aquí:

| Causa                                                        | Arreglo                                                                 |
| ------------------------------------------------------------ | ----------------------------------------------------------------------- |
| Tras compactar, el modelo no sabe qué ficheros ya escribió    | `## FILES ALREADY CREATED OR MODIFIED` obligatorio en el prompt de compactación + secciones `PLANNED FILES` / `FILES DONE` en `.agent_progress.md` |
| Nada le obliga a mirar antes de escribir                      | `rules/engineering-discipline.md` §1/§2/§6 + **RESUME PROTOCOL** en `agent/auto.md` (`git status --short` antes de crear nada) |
| Nada prohíbe stubs ni lógica duplicada                        | §4 (no dummy) y §5 (una implementación por concepto) + *final check* en las Exit Conditions |

Además `top_p: 0.8` en `agent/auto.md`: con `temperature 0.1` recorta la cola de
la distribución, así que el modelo reutiliza nombres/rutas que ya vio en el repo
en vez de inventarse variantes nuevas.

## 🚀 Sacarle más al modelo pequeño

Además del contexto, tres palancas que ya están aplicadas:

| Palanca | Qué hace |
| ------- | -------- |
| `tool_output: 400 líneas / 16000 bytes` | Los defaults de opencode son 2000 líneas / 50KB. Un solo `grep -r` podía meter ~15k tokens y disparar la compactación él solo. Lo que se pasa se guarda en disco y al modelo le llega un preview. |
| `analyze` en `mode: "all"` | Estaba en `"primary"`, así que `auto` **no podía delegarle nada** aunque su prompt lo dijera: la herramienta `task` solo ve agentes `subagent`/`all`. Ahora sí, y el análisis pesado ocurre en la ventana de contexto del subagente — a `auto` solo le vuelve la conclusión. Verifica con `opencode agent list \| grep analyze`. |
| `top_p: 0.8` en ambos agentes | Con `temperature 0.1` recorta la cola: menos rutas, APIs y nombres inventados. |

Lo que **no** conviene tocar: bajar `output` para ganar umbral (el *thinking* de
qwen se come la salida entera y devuelve respuesta vacía), ni cargar el modelo a
262k en LM Studio (el KV cache se sale de los 12GB y se cae a CPU).

## 🤖 Bucles de feedback: hacer al agente independiente

Lo que hace autónomo a un agente no es el modelo grande, son los **bucles de
feedback**: que el entorno le diga cuándo se equivoca sin que él lo razone. Un
modelo pequeño gana el doble con esto. Cuatro piezas activas:

### 1. LSP + formatter (`lsp: true`, `formatter: true`)

Tras cada edición, opencode inyecta en el output de la herramienta `edit` los
**diagnósticos reales** del fichero. Verificado en vivo — el output de una
edición que rompía un `.go` contenía:

```
Edit applied successfully.
LSP errors detected in this file, please fix:
<diagnostics> ERROR [4:14] missing ',' before newline ... </diagnostics>
```

Detalle útil: opencode trae un analizador **interno** para Go, así que esto
funciona **aunque `gopls` no esté instalado**. Para diagnósticos semánticos más
profundos (TS/Python) sí baja el LSP externo la primera vez (necesita toolchain
+ red); si falta, no rompe nada, simplemente no hay esa capa.

### 2. Plugin `verify-on-edit`

Complementa al LSP: tras editar un `.go`/`.py`/`.sh` corre un chequeo **rápido**
de parseo/compilación de ese fichero y, si falla, anexa un `❌ VERIFY-ON-EDIT`
al output de la tool — imposible de ignorar, síncrono, en el mismo turno.
Verificado: aparece junto al bloque LSP. Desactívalo con `OPENCODE_VERIFY_SKIP=1`.
La verificación **pesada** (tests, build completo) NO va aquí — va en `/verify`,
porque correr la suite tras cada edición sería demasiado lento.

### 3. Comandos (`/verify`, `/fix`, `/pr`)

Workflows en plantilla para que el modelo siga un guion en vez de improvisar:

| Comando   | Qué hace |
| --------- | -------- |
| `/verify` | Detecta el tipo de proyecto, corre build + test, reporta ✅/❌ en una línea. |
| `/fix`    | Reproduce el fallo → causa raíz → arreglo mínimo → **re-verifica** en bucle. Prohíbe silenciar el error. |
| `/pr`     | Verifica en verde → rama → commit convencional → push → `gh pr create`. Nunca abre PR en rojo. |

### 4. `AGENTS.md` por proyecto

`make init-agents` (o `bin/init-agents.sh` desde el proyecto) genera un
`AGENTS.md` con los comandos de build/test/lint **ya detectados** según el tipo
de repo. opencode lo auto-carga como contexto, así el modelo actúa sin preguntar.

### 5. `continue_loop_on_deny: true`

Si deniegas una herramienta (p.ej. un `git push`), el agente sigue trabajando y
busca otra vía en vez de abortar la tarea entera.

### 6. Thinking híbrido (auto sin thinking, analyze con thinking)

El bug de "respuesta vacía": con thinking ON, el bloque de razonamiento de
qwen3.5 se come el presupuesto de `output` entero y devuelve `content` vacío
(medido: un `17*23` gastó los 300 tokens de output en `reasoning` y no contestó).

Solución por-agente: el **ejecutor** `auto` corre **sin** thinking (rápido, sin
el bug), y el **analista** `analyze` lo conserva (donde el razonamiento paga).

```jsonc
// opencode.jsonc
"agent": { "auto": { "reasoningEffort": "none" } }   // <- clave TOP-LEVEL, camelCase
```

Dos cosas que costó descubrir (verificadas capturando el body HTTP real):

1. **`reasoningEffort` va como clave de nivel superior del agente**, camelCase —
   NO anidada en `options`, NO en snake_case. opencode la mapea a
   `reasoning_effort` en el cuerpo de la petición. En cualquier otra ubicación
   se ignora en silencio.
2. **Solo `reasoning_effort` funciona con LM Studio.** Probados y descartados:
   `/no_think` en el prompt, `chat_template_kwargs.enable_thinking`,
   `enable_thinking` top-level — LM Studio no los honra. `reasoning_effort:"none"`
   → 0 tokens de razonamiento, respuesta directa.

Verificado end-to-end: `auto` envía `reasoning_effort='none'` y responde `391`
directo; `analyze` no lo envía y conserva el thinking.

### ⚠️ `instructions` usa rutas ABSOLUTAS

Las rutas relativas de `instructions` se resuelven contra el **directorio del
proyecto**, no contra `~/.config/opencode`. Con `"rules/*.md"` no se cargaba
nada y no da ningún error — falla en silencio. Por eso está como
`"{env:HOME}/.config/opencode/rules/engineering-discipline.md"`.

Verifica que están cargadas (debe citar la sección 4):

```bash
opencode run "Without using any tools: do your system instructions contain a section titled 'No dummy, no placeholder, no fake'?"
```

## Modelos actualmente en pcgamer (12GB VRAM)

Verifica siempre con `make models` — declarar en `opencode.jsonc` un modelo que
no está cargado **no da error**: LM Studio cae en silencio al modelo cargado.

| Modelo                              | Estado     | Uso                          |
| ----------------------------------- | ---------- | ---------------------------- |
| **qwen/qwen3.5-9b**                 | cargado    | Coding principal + small_model |
| **google/gemma-4-12b-qat**          | no cargado | Alternativa (Q4_0)           |
| **text-embedding-nomic-embed-v1.5** | no cargado | Embeddings                   |

## 🧮 Cuándo compacta opencode (la fórmula real)

Extraída del binario de opencode `v1.18.4` (`SessionCompaction.isOverflow`):

```js
usable = limit.input ? (limit.input - compaction.reserved)
                     : (limit.context - min(limit.output, 32000))

overflow cuando  tokens_totales >= usable
```

Tres consecuencias que no son obvias:

1. **No compacta al llegar a `context`, sino a `context − output`.** El
   presupuesto de salida se reserva entero, siempre.
2. **`compaction.reserved` se ignora** salvo que declares `limit.input` en el
   modelo. Sin `limit.input` esa rama no se ejecuta: lo estábamos poniendo y no
   hacía nada. Por eso ya no está en el config.
3. El **% de la barra de la TUI** se calcula contra `limit.context`, no contra
   el umbral. Con la config actual la compactación salta al **74 %** de la barra
   (45616 / 62000): la barra nunca llega al 100 %, y eso es correcto.

Con `output: 16384`, cada token que le quites a `context` te lo comes doble en
la conversación útil. Estado actual:

| Config                     | Umbral real           | Conversación útil |
| -------------------------- | --------------------- | ----------------- |
| antes: 48000 / 16384       | 31616                 | —                 |
| **ahora: 62000 / 16384**   | **45616**             | **+44 %**         |

Compruébalo en cualquier momento con:

```bash
make ctx    # n_ctx cargado en LM Studio vs. lo declarado + umbral calculado
make bench  # tokens/seg del modelo cargado
```

La restricción dura es `context <= loaded_context_length` del servidor
(**70144** ahora mismo). Si subes el Context Length en LM Studio, sube `context`
aquí dejando ~8k de colchón; **no bajes `output` de 16384** (ver más abajo).

## ⚠️ El bug de "no responde nada" con contexto grande

Síntoma: la sesión avanza bien y de pronto el modelo devuelve **una respuesta
vacía** y no continúa.

Causa (medida contra el server): el bloque de *thinking* de qwen3.5 **crece con
el tamaño del prompt**. Con un prompt de 44k tokens gastó los **8192 tokens de
output enteros dentro de `reasoning_content`** y devolvió `content` vacío con
`finish_reason=length`. Con un prompt corto la misma petición contesta sin
problema (~400 tokens). No es un cuelgue ni un timeout: es el presupuesto de
salida consumido por el razonamiento.

Además `context` + `output` del `opencode.jsonc` tienen que caber **los dos**
dentro del `loaded_context_length` de LM Studio, o el server responde
`400 exceed_context_size_error`.

Por eso los límites actuales son `context: 48000` / `output: 16384`
(= 64384, por debajo de los 72192 cargados): `output` doble le da aire para
cerrar el razonamiento y contestar, y `context` más bajo fuerza la
compactación **antes** de llegar a ese punto.

> Si subes el Context Length en LM Studio, sube también estos dos valores
> manteniendo `context + output` con margen por debajo del nuevo `n_ctx`.

## ⚠️ Lo más importante: settings de carga en LM Studio (en pcgamer)

La lentitud NO es el modelo, es cómo estaba cargado. El `opencode.jsonc` solo
define límites de contexto **del lado del cliente**; el tamaño real del KV cache
lo fija LM Studio **al cargar el modelo**. En LM Studio (pestaña del modelo →
*Load* / *My Models → gear*):

1. **Context Length**: baja de 262144 (256k) a algo que quepa en VRAM.
   Actualmente cargado a **72192**; 32000–48000 va más holgado y deja el KV
   cache entero en GPU. ← el mayor ahorro de VRAM.
2. **Flash Attention**: **ON**.
3. **K/V Cache Quantization**: **Q8_0** (mitad de VRAM del cache, sin pérdida notable).
4. **GPU Offload**: **máximo** (todas las capas en GPU). Si no caben, baja el quant.
5. Prefiere GGUF **Q4_K_M** o **Q5_K_M** en vez de **Q8_0** para el 9B
   (Q8 pesa ~9.5GB y no deja espacio para el contexto en 12GB).

Con esto el 9B corre 100% en GPU y responde varias veces más rápido.

> **Nota:** cambiar el valor de Context Length NO re-asigna el KV cache — hay que
> hacer **eject + load** del modelo para que tome efecto. Verifica con:
> `curl -s http://pcgamer:1234/api/v0/models` (campo `loaded_context_length`).

## 📊 Benchmark del tuning (qwen3.5-9b, RTX 12GB)

Medido con `/api/v0/chat/completions` (mismo prompt, `max_tokens=200`):

| Configuración                              | tokens/seg      |
| ------------------------------------------ | --------------- |
| Q8_0 · 50k (estado inicial)                | 26.6            |
| Q4_K_M · 50k                               | 34.4            |
| **Q4_K_M · 35k + FlashAttn + KV Q8**       | **49.0**        |
| Q4_K_M · 35k — con contexto lleno (~7k tok)| 47.0 (TTFT 0.65s) |
| **Q4_K_M · 70144 (estado actual)**          | **52.1** (TTFT 0.20s) |

Que a 70k siga a ~52 tok/s confirma que el KV cache sigue **entero en GPU**:
doblar el contexto no costó velocidad, así que no hay razón para volver a 35k.

~85% más rápido que el inicio. La clave fue que **pesos + KV cache entren enteros
en los 12GB de VRAM** (sin offload a CPU): Q8_0 pesaba ~9.5GB y no dejaba sitio;
Q4_K_M (~5.5GB) + KV de 35k en Q8 (~2.5GB) ≈ 8GB → cabe con margen. Que el decode
apenas baje (49 → 47) con el contexto lleno confirma que no hay offload.
