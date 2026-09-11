# opencode-config

Configuración de [opencode](https://opencode.ai) versionada con git, apuntando a
un servidor local de modelos en `pcgamer` (vía Tailscale, 12GB VRAM).

> ⚠️ **El backend es `llama-swap` + llama.cpp, no LM Studio.** Lo fue, y buena
> parte de este README todavía habla de LM Studio en secciones históricas.
> Cuando una de esas secciones contradiga a *Modelos actualmente en pcgamer*,
> **gana esa**. Lo verificas en un segundo:
>
> ```bash
> curl -s http://pcgamer:1234/v1/models | grep owned_by   # -> "llama-swap"
> make models                                             # ids reales vs declarados
> ```
>
> Lo que más cambia en la práctica: un id de modelo que no existe devuelve
> **404**, no un fallback silencioso. La clave del provider sigue llamándose
> `lmstudio` en `opencode.jsonc` por no tocar todas las referencias
> `lmstudio/...`; es un nombre heredado.

El repo es la **fuente de verdad**. `make install` reemplaza los archivos en
`~/.config/opencode` por *symlinks* hacia este repo.

## Uso

```bash
make install       # crea los symlinks (respalda lo previo)
make status        # ver estado de los symlinks
make test-conn     # ping al server de modelos en pcgamer
make models        # lista modelos disponibles
make ctx           # contexto real del server vs. lo declarado + umbral
make bench         # tokens/seg del modelo cargado
make init-agents   # genera AGENTS.md en el proyecto actual (DIR=... o CWD)
make test-plugins  # tests de los plugins que pueden bloquear al agente
make mcp           # estado de los servidores MCP + ping a los remotos
make uninstall     # quita los symlinks
make restore       # restaura el ultimo respaldo
```

## Qué se versiona

| Archivo / carpeta        | Rol                                                        |
| ------------------------ | ---------------------------------------------------------- |
| `opencode.jsonc`         | Config principal: provider, modelos, permisos, LSP/formatter |
| `agent/auto.md`          | Agente primario de coding (`qwen-35b`)                     |
| `rules/engineering-discipline.md` | Reglas anti-slop inyectadas en **todos** los agentes |
| `rules/knowledge-protocol.md` | Anti-alucinacion: mirar antes de escribir, con presupuesto |
| `command/*.md`           | Comandos: `/verify`, `/fix`, `/pr`, `/review`              |
| `plugin/verify-on-edit.ts` | Chequeo de compilación/lint tras cada edición            |
| `plugin/anti-slop-guard.ts` | **Impide** (no "pide") crear duplicados y ficheros de relleno |
| `plugin/ground-truth.ts` | Inyecta el estado real del repo en cada turno              |
| `plugin/slim-tools.ts`   | Recorta `bash`, quita reglas de codigo a agentes NON-CODING, PATH |
| `plugin/ticket-format.ts`| Renumera las secciones del ticket de Jira                  |
| `test/plugins.mjs`       | Tests de ambos (`make test-plugins`). Fuera de `plugin/` a proposito: opencode carga como plugin lo que hay ahi dentro. |
| `bin/docs.sh`            | Consulta de paquetes (npm/PyPI/crates/go/MDN/wiki)         |
| `bin/web.sh`             | Busqueda web (`search`) y lectura de una pagina (`read`)   |
| `bin/webfetch`, `bin/websearch` | Alias de shell para dos nombres de HERRAMIENTA que el modelo escribe en bash |
| `skill/review-changes/`  | Skill: auditar un diff — verificar lo que afirma y que se quedo sin actualizar |
| `skill/stop-and-verify/` | Skill: cuando PARAR porque no lo sabes, y que cuenta como prueba |
| `skill/web-research/`    | Skill: como buscar en internet y que fuentes valen         |
| `skill/unstick/`         | Skill: algo fallo dos veces — diagnosticar en vez de repetir |
| `skill/new-project/`     | Skill: arrancar un proyecto de cero sin escribir 10 ficheros a ciegas |
| `skill/failing-test/`    | Skill: un test en rojo se arregla, no se apaga               |
| `skill/long-running/`    | Skill: servidores y procesos que no terminan solos           |
| `skill/explore-codebase/`| Skill: orientarse en un repo ajeno con presupuesto           |
| `skill/dependencies/`    | Skill: añadir/subir paquetes sin inventarse versiones        |
| `skill/enough-context/`  | Skill: ¿tengo lo necesario para resolver esto? y si no, buscarlo |
| `skill/jira-ticket/`     | Skill: Historias de Usuario para Jira (era `agent/ticket.md`) |
| `plugin/loop-breaker.ts` | **Corta** el bucle: mismo comando + misma salida = bloqueado |
| `plugin/tokens-per-second.ts` | Toast con throughput (tok/s) tras cada respuesta      |
| `templates/AGENTS.md`    | Plantilla de contexto por-proyecto (`make init-agents`)    |
| `bin/init-agents.sh`     | Genera un `AGENTS.md` con los comandos ya detectados       |

## ⚖️ `auto` vs `build`: medir antes de asumir que el de serie es mejor

La sospecha (2026-09-11) era que el agente `build` de opencode funcionaba mejor
que `auto`. Antes de tocar nada se midió: mismo modelo (`qwen-35b`), las 4
tareas del bench, `build` contra el `auto` de entonces. Para eso
`bench/run-model.sh` acepta ahora un tercer argumento (el agente) y
`metrics.py` saca `turns`, `prompt0` (input del primer turno = coste fijo real
del prompt) y `out` (output + reasoning de la sesión):

```bash
make bench-models MODEL=lmstudio/qwen-35b TAG=build AGENT=build
make bench-models MODEL=lmstudio/qwen-35b TAG=auto  AGENT=auto
```

### Qué es `build` para este modelo, exactamente

- **Prompt**: opencode elige el prompt de sistema por el id del modelo. `qwen-35b`
  no contiene `gpt`, `claude` ni `gemini`, así que le toca el genérico
  (extraído del binario con `strings`): ~1.3k tokens, orientado a tarea —
  entender el código por los nombres de fichero, copiar las convenciones del
  fichero vecino, no asumir que una librería está instalada, buscar mucho,
  **lanzar las tool calls independientes en paralelo**, correr lint/typecheck al
  acabar, no comentar, no hacer commit sin que se pida.
- **Tools**: todas, incluidas `task`, `todowrite` y `webfetch` (~1.5k tokens de
  esquemas que `auto` no paga).
- **Sampling**: NO manda `temperature` ni `top_p` para qwen (opencode no tiene
  default para este id), así que corre con los de llama.cpp: 0.8 / 0.95 / top_k
  40 / min_p 0.05. `auto` manda 0.6 / 0.95.
- **Razonamiento**: da igual lo que mande nadie — el servidor corre con
  `--reasoning-budget 700` (`curl pcgamer:1234/running`), que es por lo que
  `reasoningEffort` nunca midió nada.

### Lo que salió (ronda 1, n=1 por celda)

| tarea | build | auto (antes) |
| --- | --- | --- |
| redtest | PASS · 90s · **5 turnos** | PASS · 98s · **13 turnos** |
| newproj | PASS · 59s · 6 turnos | PASS · 85s · 10 turnos |
| lookup | PASS · 45s · 2 turnos | PASS · 63s · 2 turnos |
| ticket | **FAIL** (escribió el fichero en otro directorio) · 98s | PASS · 91s |
| `prompt0` | 12.97k tok | 12.67k tok |

`build` **no era más correcto** (3/4 contra 4/4). Era más **barato por tarea**:
mismo arreglo, la mitad de turnos. Y la secuencia de llamadas de `auto` en
`redtest` decía exactamente dónde se iban:

```
$ mkdir -p .agent && ... cat .agent/progress.md      ← 2 turnos de fichero de progreso
$ printf '# GOAL ...' > .agent/progress.md              antes de leer una línea de código
→ Read calc.go / calc_test.go / go.mod                 (build los lee en UN mensaje)
$ go test -v
← Edit calc.go  ← Edit calc.go
$ go test -v                                           ← aquí ya estaba en verde
$ go test -v | grep -iE "error|exception|fail"         ← 6 turnos de ceremonia
$ git status --short                                     de "definition of done"
$ git diff
$ git status
$ go test -v | grep -i warn
$ cat > .agent/progress.md
```

No era el modelo: era el prompt pidiendo un ritual desproporcionado, y **una
sola tool call por mensaje** (regla heredada de gpt-oss, que producía JSON
inválido; Qwen3.6 + llama.cpp parsean varias sin problema — `build` lo hizo en
todos los runs).

### Lo que cambió en `agent/auto.md`

- **Se trajo de `build`**: orientarse por nombres de fichero antes de editar,
  copiar el fichero vecino, comprobar el manifest antes de usar una librería,
  **tool calls independientes en un solo mensaje** (las dependientes, de una en
  una), lint/typecheck al final, sin comentarios, sin commits sin pedir.
- **Se fue**: todo lo que ya está en `rules/*.md` (buscar antes de escribir,
  edit > write, sin stubs, error = defecto) y las narrativas de incidentes —
  viven aquí, donde las lee un humano; al modelo le basta la regla.
- **Fichero de progreso condicional**: solo para tareas de más de ~8 llamadas
  o más de 2 ficheros. Cierra la pregunta abierta de *El agente NO crea el
  fichero de progreso en tareas cortas*.
- **"Done" se lee de la salida que ya tienes**: nada de segundos `grep` sobre
  los logs ni `git diff`; `git status --short` es el único comando extra.
- Cuerpo: 12.3k → 7.3k chars. Coste fijo por turno: **12.67k → 11.35k tokens**
  (−1.3k contra el `auto` anterior, −1.6k contra `build`).

### Ronda 2, con el bench arreglado

Al mirar los runs salieron dos defectos **del bench**, no de los agentes:

1. Los fixtures eran subdirectorios gitignorados de este repo: `git status
   --short` salía vacío aunque el agente acabara de editar `calc.go`, y el
   agente se pasaba 5 turnos con `git diff` / `ls-files` intentando explicar
   por qué "no hay cambios". Ahora cada fixture es su propio repo con un commit
   inicial (`setup.sh`), y `run.txt` / `.seconds` van ignorados.
2. `.test_md5` a la vista: `build` se pasó **8 turnos** intentando adivinar de
   qué era el hash (un run de 174s). Ahora vive en `.git/test_md5`.
3. `score.sh` contaba `[POR CONFIRMAR: stack (React, Vue...)]` como "stack
   inventado" — un stack marcado como no confirmado es justo lo que pide la
   skill. Se ignoran esas líneas.

| tarea | build | auto (nuevo) |
| --- | --- | --- |
| redtest | PASS · 68s · 6 turnos | PASS · 69s · 5 turnos |
| newproj | PASS · 61s · 9 turnos | PASS · 74s · 8 turnos |
| lookup | PASS · 41s · 2 turnos | PASS · 41s · 3 turnos |
| ticket | PASS · 75s · 4 turnos | PASS · 89s · 6 turnos |
| `prompt0` | 12.94k tok | 11.32k tok |

Acumulado: `build` 7/8, `auto` nuevo 8/8 (ronda 1 + ronda 2), a turnos
equivalentes y con 1.6k tokens menos de prompt fijo por vuelta. El `auto` nuevo
además carga skills que `build` ignora (`failing-test` en redtest, `new-project`
en newproj): el andamiaje se dispara.

**Honestidades**: n=2 por celda. La varianza entre runs iguales es grande —
`build` hizo `redtest` en 5 turnos una vez y en 17 otra — así que los segundos
y los turnos son orientativos; los PASS/FAIL son lo único firme. Y las dos
rondas no son idénticas (la 2 lleva los fixtures arreglados), por eso se
presentan por separado.

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

## 🧠 Conocimiento: que el modelo lo MIRE en vez de inventarselo

El fallo de un modelo local de 9B/20B casi nunca es "razona mal". Es que
**recuerda mal**: no tiene guardada la firma exacta de una libreria, ni el flag
de un CLI, ni la clave de un fichero de config. Y cuando no lo sabe **no falla,
inventa** — con toda la confianza del mundo. Un `pkg.DoThing()` que no existe
compila perfectamente en su cabeza.

La solucion no es un modelo mas grande ni mas *thinking*. Es darle una regla
para **mirarlo**, barata y acotada, en `rules/knowledge-protocol.md` (se inyecta
en todos los agentes junto a `engineering-discipline.md`).

### Las tres piezas

**1. Que puede escribir de memoria y que no.** La distincion importa porque
"comprobalo todo" mata la velocidad:

| De memoria (no lo mires)                    | Miralo SIEMPRE                                      |
| ------------------------------------------- | --------------------------------------------------- |
| Sintaxis, control de flujo, algoritmos       | Firmas de librerias de terceros, parametros, returns |
| Lo que ya esta en la conversacion            | Flags de CLI, env vars, claves de config, rutas      |
| Lo que leyo de un fichero este mismo turno   | Comportamiento que depende de la version             |
|                                              | Cualquier cosa de ESTE proyecto                      |

Y un *tripwire* explicito: antes de escribir un identificador, "¿donde lo he
visto?". Si la respuesta no es un `file:line` o la salida de un comando de esta
sesion, esta adivinando.

**2. Escalera de lookups, ordenada por coste.** Para en el primer escalon que
conteste — no es "busca en Google", que es justo el escalon mas caro:

```
0. contexto / .agent_progress.md / AGENTS.md      gratis
1. el repo:    grep -rn "Symbol" . | head -20     ← mejor doc que existe: compila HOY
2. el paquete: go doc / help(pkg.x) / *.d.ts      ← la version REALMENTE instalada
3. la tool:    <cmd> --help | grep -i <cosa>
4. un probe de 3 lineas que EJECUTA               ← el oraculo mas rapido
5. la web: web.sh search / web.sh read            ← ultimo, cuesta segundos y contexto
```

**3. Presupuesto: dos lookups y a escribir.** Es la mitad que hace que esto no
lo vuelva lento. Despues del segundo, escribe el codigo y deja que le corrijan
el LSP, `verify-on-edit` y los tests — ese bucle ya existe aqui y es mas rapido
y mas exacto que seguir leyendo. Excepcion sin presupuesto (donde equivocarse es
silencioso y caro): comandos destructivos, migraciones, auth/cripto, dinero.

### Como encaja con lo que ya habia

- **`auto` no tiene la herramienta `webfetch` a proposito** (le costaba su
  esquema en cada turno). Lo que si tiene, por `bash`, es `web.sh search` y
  `web.sh read`: 0 tokens de esquema hasta usarlos y salida truncada de serie
  (4000 chars una busqueda, 6000 una pagina). Su §2b lo dice con presupuesto:
  una busqueda + una lectura, dos rondas como maximo, y el dato a
  `# VERIFIED FACTS` con su fuente — o `UNVERIFIED`, que es respuesta valida.
  Esto lo hacia el subagente `analyze` hasta el 2026-09-07; ver mas abajo por
  que se elimino.
- **`.agent_progress.md` gana una seccion `# VERIFIED FACTS`**: cada dato que
  costo un lookup se apunta con el comando que lo probo. El contexto se compacta;
  el fichero no. Mirar tres veces la misma firma es como un modelo rapido se
  vuelve lento.

### Coste, dicho claro

**1.231 tokens fijos por turno** (3,1% del umbral de 39.808), MEDIDO por
ablacion sobre una misma peticion leyendo `usage.prompt_tokens` del server.
(La primera estimacion decia ~920: contar palabras x4/3 se queda corto con
markdown y bloques de codigo.) No es gratis y no esta medido contra un
benchmark todavia: el benchmark de `Chunk()`/`Truncate()`
no lo detecta porque son tareas de **stdlib de Go**, justo el caso donde el
modelo SI recuerda bien. Para medir esto hace falta una tarea contra una libreria
de terceros, que es donde aparece la alucinacion.

Comprueba al menos que la regla esta cargada (debe citar la escalera):

```bash
opencode run "Without using any tools: what are the 5 rungs of your lookup ladder?"
```

## 🔒 De reglas a restricciones: `plugin/anti-slop-guard.ts`

Una regla en el prompt cuesta tokens en CADA turno y el modelo la cumple *casi*
siempre. Un hook cuesta **cero tokens** y la cumple **siempre**. Todo lo que se
pueda mover de `rules/` a un hook, se mueve.

Lo que el guard impide (lanzando una excepcion, con un mensaje que le dice al
modelo que hacer en su lugar):

| Situacion                                        | Que pasa                                        |
| ------------------------------------------------ | ----------------------------------------------- |
| `write` sobre un fichero que existe y NO ha leido | **Bloqueado** → "leelo y usa `edit`"            |
| `write` sobre un fichero que SI ha leido          | Permitido: reescribir informado es legitimo      |
| `SUMMARY.md`, `ANALYSIS.md`, `RESUME.md`…         | **Bloqueado**: el resumen va en el chat          |
| `foo_v2.py` **existiendo** `foo.py`               | **Bloqueado** → "edita `foo.py`"                 |
| `brand_new.go` sin `brand.go`                     | Permitido (nombre legitimo, no un duplicado)     |
| Un `edit`/`write` que borra `func`/`def`/`class`  | Aviso ⚠️ inline con los simbolos que se llevo    |

`.agent_progress.md` esta exento (se reescribe entero a proposito). Kill switch:
`OPENCODE_GUARD_OFF=1`. Tests: `make test-plugins` (16 casos).

### Lo que se comprobo del API de hooks (v1.18.19)

Esto no venia en ninguna documentacion; se saco con un plugin sonda y un proxy
que captura el body real de cada peticion:

| Hook                                    | ¿Sirve para esto?                                    |
| --------------------------------------- | ---------------------------------------------------- |
| `permission.ask`                        | ❌ **NO se dispara** si el permiso esta en `allow`. Enforcement por aqui es un no-op silencioso. |
| `tool.execute.before` + `throw`          | ✅ **Aborta la herramienta** y el error llega al modelo, que se corrige solo. Es la via buena. |
| `chat.params`                           | ⚠️ Funciona para campos conocidos (`temperature: 0.42` llego al wire) pero `options.reasoning_effort` **NO** sobreescribe al del agente. |
| `experimental.chat.messages.transform`  | ✅ El texto inyectado llega al wire.                  |

> Por eso NO hay "reasoning effort adaptativo" (subir a `medium` solo tras un
> fallo): se probo, y el mecanismo no existe por esa via. Mejor no tenerlo que
> tenerlo creyendo que funciona.

Un detalle que costo una prueba: **el modelo copia lo que pongas en el mensaje
de error**. En la sonda aparecio una ruta truncada (`.../existing.txt`) en el
error y el modelo la uso tal cual en su siguiente llamada. Por eso los mensajes
del guard usan rutas **relativas** y cortas.

## 🚨 Las reglas anti-alucinacion hacian que el modelo SE NEGARA a usar los MCP

El sintoma: con `duckduckgo` y `jiraAdmin` **conectados** (ambos en verde en el
panel de la TUI), el modelo contestaba:

> "I've checked the repository and the environment for any configured MCP
> servers, but none are present."

Su propio razonamiento delataba la causa:

> *"We need to use jiraAdmin tools: jiraAdmin_confluence_search? But user wants
> list of MCPS. Maybe we should ask for server name. **According to rules,
> cannot guess.** So respond that no MCPs found."*

O sea: **veia la herramienta, la nombraba bien, y se negaba a llamarla citando
`knowledge-protocol.md`.** El *tripwire* ("antes de escribir un identificador,
¿donde lo has visto? si no es un `file:line`, estas adivinando") se le aplicaba
al nombre de una herramienta de su PROPIA lista.

Es la regla anti-alucinacion produciendo justo el fallo que venia a evitar, del
reves: en vez de inventarse capacidades, negaba las que tenia.

Arreglo — una excepcion explicita en `rules/knowledge-protocol.md`:

> **This rule does NOT apply to your own tools.** Every tool available to you is
> listed in this prompt with its name and parameters: that IS the source.
> Calling one is never "guessing", and a tool you can see is never "not found".

Con el caso real escrito dentro como ejemplo, y una linea en `agent/auto.md`:
si hay herramientas MCP en tu lista, estan conectadas — llamalas; si te
equivocas de herramienta, el error te lo dice mas rapido que preguntar.

Verificado con la MISMA peticion que fallaba: ahora llama a
`jiraAdmin_confluence-search {"query":"test"}` en vez de negar que existan MCPs.

> **Leccion general:** una regla de "no te inventes cosas" puede volverse una
> regla de "no uses lo que tienes". Si añades restricciones a un modelo pequeño,
> comprueba tambien que no le impidan hacer su trabajo — no solo que eviten el
> fallo que te preocupaba.

## 🌐 `jiraAdmin` apuntaba a `localhost` y el servidor esta en OTRA maquina

`"url": "http://localhost:9001/mcp"` con el servidor corriendo en otro PC. Aqui
no habia nada escuchando en el 9001, de ahi el
`SSE error: Unable to connect`.

Localizado escaneando el 9001 en todos los hosts de `tailscale status`:

```
jaenpc:9001   -> 000
amaris:9001   -> 405   <- un endpoint MCP responde 405 a un GET
server:9001   -> 000
pcgamer:9001  -> 000
```

Y el handshake lo confirma: `serverInfo {"name":"mcp-jira","version":"2.0.0"}`,
con 5 herramientas: `jira-ticket-details`, `confluence-search`,
`confluence-read`, `confluence-write`, `confluence-database-rows`.

Las herramientas le llegan al modelo como `<servidor>_<herramienta>`, o sea
`jiraAdmin_confluence-search`.

URL corregida a `http://amaris:9001/mcp`. Comprueba el estado con `make mcp`,
que ademas hace un ping REAL a los remotos (405 = bien; 000 = servidor caido o
la maquina fuera de la VPN).

## ❓ "Los MCP no funcionan" — no, es el MODELO eligiendo mal la herramienta

Sintoma: pides "revisa los MCP" y el modelo contesta que no hay ninguno
configurado, con los servidores en verde en el panel.

**Los MCP funcionan.** Probado end-to-end:

```
⚙ jiraAdmin_confluence-search {"query":"onboarding","limit":25}
→ "Se encontraron 25 resultados"
```

Lo que falla es **como elige la herramienta un modelo de 20B**: por coincidencia
de nombres. Tu frase lleva "MCP", y existen tools llamadas `list_mcp_resources`
y `list_mcp_resource_templates` -> las llama. Devuelven vacio (estos servidores
exponen TOOLS, no RESOURCES) -> concluye que no hay nada. Nunca prueba
`jiraAdmin_confluence-search`, que tiene delante y funciona.

Un modelo grande razona "resources != tools". Este empareja nombres.

### Lo intentado, con resultado real

| Intento | Resultado |
| ------- | --------- |
| `tools: { list_mcp_resources: false }` | ❌ NO las quita. (Las tools del servidor, como `duckduckgo_search`, SI se filtran — es una asimetria del motor.) |
| `tool.definition` para acortar su descripcion | ❌ El hook **no se dispara** para tools de MCP, solo para las nativas. Era codigo muerto; se quito. |
| Decirselo en el prompt | ⚠️ Se cumplio a medias. Probabilistico, como toda regla de prompt en este modelo. |
| `tool.execute.before` + `throw` | ⚠️ **Parcial.** Dispara y bloquea si el argumento `server` es valido; si el modelo manda `server:"all"`, opencode falla ANTES con su propio error y el hook no corre. |

### La conclusion honesta

El problema no esta en la capa de herramientas: **"¿que MCPs tengo?" es una
pregunta de introspeccion, y este modelo no sabe enumerar sus propias
herramientas.** Ninguna configuracion arregla eso.

La distincion practica:

- **USAR el MCP** → funciona. Pide algo concreto:
  `usa jiraAdmin para leer el ticket FIFPLATFOR-10937`
- **INVENTARIAR los MCP** → no preguntes al modelo. `make mcp` te da la verdad
  en un comando, sin modelo de por medio.

### Coste que no se puede evitar

Las 3 tools de fontaneria cuestan **197 tok/turno en TODOS los agentes** y no se
pueden quitar mientras haya un servidor MCP declarado. Si no usas MCP en una
sesion, la unica palanca real es `enabled: false` en el servidor.

### Ojo con `.agent/progress.md` entre sesiones

Durante estas pruebas el modelo mando `server: "BLOCKED_MCP_PLUMBING"` — un
string de un error de una prueba ANTERIOR, que se habia quedado escrito en
`.agent/progress.md` y se leyo en la sesion siguiente. El fichero persiste a
proposito (es lo que sostiene el resume), pero **lo que se escriba ahi vuelve al
modelo mas tarde**. Si una sesion deja basura ahi, la siguiente se la come.

## 🔌 MCP: `enable` NO existe, es `enabled`

Los dos servidores estaban declarados con `"enable": true`. **La clave correcta
es `enabled`**. `enable` no da error: se ignora en silencio.

Daba igual mientras el valor fuera `true` (por defecto estan encendidos), pero
un `"enable": false` **no habria desactivado nada** — habrias creido que un
servidor estaba apagado teniendolo encendido. Comprobado tras el arreglo:
con `enabled: false`, `opencode mcp list` ya muestra `○ disabled`.

### `connected` no quiere decir `funciona`

```
● ✓ duckduckgo  connected      <- arranca y hace handshake...
● ✗ jiraAdmin   failed         <- SSE error: Unable to connect
```

`✓ connected` solo dice que el proceso arranca y responde al handshake. NO dice
que sus herramientas devuelvan datos. duckduckgo salia en verde y fallaba en
CADA llamada.

Y `✗ failed` en `jiraAdmin` tampoco es un fallo de configuracion: no habia nada
escuchando en el 9001 (`curl` -> HTTP 000, `lsof` -> vacio). El servidor de Jira
hay que levantarlo ANTES de abrir opencode.

Comprueba las dos cosas de golpe con:

```bash
make mcp     # estado de opencode + ping real a los servidores remotos
```

## 🔎 La busqueda web estaba ROTA (y no se sabia)

El escalon 5 del knowledge-protocol era "busca en la web", apoyado en el MCP
`ashdev/duckduckgo-mcp-server`. **No funcionaba.** Llamando al servidor por
stdio (JSON-RPC, `tools/call name=search`):

```
"Failed to retrieve results from DuckDuckGo:
 https://html.duckduckgo.com/html 202 Ratelimit"
```

Y por `curl` directo, DuckDuckGo sirve un **captcha de patos** a esta maquina,
tanto en GET como en POST. O sea: `analyze` tenia una herramienta de busqueda
que solo devolvia errores, y encima costaba **197 tokens/turno** en TODOS los
agentes (las 3 tools de fontaneria MCP que opencode inyecta en cuanto declaras
un servidor — el README viejo decia ~371, el valor medido es 197).

**El MCP de busqueda esta DESACTIVADO** (`enabled: false`), no borrado: asi no
cuesta tokens ni turnos, y reactivarlo es cambiar un `false` por un `true`.

Verificado end-to-end con el modelo, por si quedaba duda de si el problema era
el cliente: `duckduckgo_search` SI llega al modelo, el modelo SI la llama —
cuatro veces, reformulando la query — se come cuatro errores y termina diciendo
"no encontre informacion publica sobre el protocolo MCP de Anthropic". O sea:
197 tok/turno y varios turnos perdidos a cambio de una respuesta falsa.

En su lugar, `bin/docs.sh`, que consulta los registros oficiales — tienen API
JSON, sin clave y sin captcha:

```bash
docs.sh npm express        # version, repo, si trae tipos, deps
docs.sh py requests        # version, python requerido, docs
docs.sh rs serde           # version, docs.rs
docs.sh go github.com/gin-gonic/gin   # ultimas versiones publicadas
docs.sh mdn fetch          # APIs web
docs.sh wiki <termino>
```

Se llama **desde `bash`**, asi que cuesta **0 tokens de esquema** hasta que se
usa — al reves que un MCP, que mete su esquema en cada turno. Los cuatro
registros estan verificados funcionando.

> Lo que NO cubre: busqueda web general (mensajes de error raros, blogs). Para
> eso haria falta un backend con clave (Brave/Serper/Tavily). Scraping de
> DuckDuckGo ya no es viable desde aqui. Mientras tanto, el escalon 5 es
> `docs.sh` y `webfetch` sobre una URL que ya conozcas (solo `analyze`).
>
> **Desfasado**: la seccion siguiente lo arregla con `web.sh`, y desde el
> 2026-09-07 `analyze` ya no existe.

## 🌍 Ahora SI hay busqueda web — y dos skills que dicen cuando usarla

La seccion de arriba terminaba en "no hay busqueda web general desde aqui". Ya
no es cierto, y hacia falta arreglarlo: el modelo local razona bien pero
**recuerda mal**, y el escalon final del knowledge-protocol no tenia con que
ejecutarse.

### Lo que se comprobo (todo con `curl`, no de oidas)

| Via                                   | Estado hoy |
| ------------------------------------- | ---------- |
| `https://mcp.exa.ai/mcp` (`web_search_exa`) | ✅ responde SIN clave, con titulo + URL + extractos del contenido |
| `https://html.duckduckgo.com/html/`   | ✅ 200 desde el Mac (8 resultados). Lo que fallaba era el **contenedor** del MCP, no la maquina |
| Herramienta `websearch` de opencode   | ❌ **no existe** en esta instalacion |
| MCP `duckduckgo`                       | ❌ sigue roto: `202 Ratelimit`. Usa `lite.duckduckgo.com` (202), no `html.` (200) — por eso web.sh sí funciona. **Apagado** de nuevo tras verificarlo |

Lo de `websearch` conviene explicarlo porque es contraintuitivo: el permiso
`"websearch": "allow"` esta en el config desde hace tiempo, pero **la
herramienta no llega al modelo**. Verificado:

```bash
opencode debug agent build | python3 -c "import sys,json;print(json.load(sys.stdin)['tools'])"
# -> ... 'webfetch': True, 'todowrite': True, 'skill': True     (sin websearch)

OPENCODE_ENABLE_EXA=1 opencode debug agent build | python3 -c "import sys,json;print(json.load(sys.stdin)['tools'])"
# -> ... 'websearch': True, ...
```

O sea: se enciende con `OPENCODE_ENABLE_EXA=1` (o `OPENCODE_EXPERIMENTAL=1`, que
ademas mete `execute`, `lsp` y `plan_exit`). No se ha encendido **a proposito**:
seria un esquema de herramienta mas en el prompt de CADA turno, que es
exactamente lo que se lleva meses recortando aqui.

### `bin/web.sh` — la misma jugada que `docs.sh`

Mismo backend que usaria `websearch` (Exa), pero por `bash`: **0 tokens de
esquema** hasta que se llama.

```bash
web.sh search "opencode SKILL.md frontmatter fields"   # titulo + URL + extractos
web.sh read https://opencode.ai/docs/skills/           # esa pagina en texto plano
```

Detalles que importan:

- `search` usa Exa y **cae solo** a DuckDuckGo si falla (`WEB_ENGINE=ddg` fuerza
  el respaldo para comprobar que sigue vivo). El respaldo da titulo + URL, sin
  extracto — de ahi se sigue con `read`.
- `read` se queda con `<main>`/`<article>` cuando existen. Sin eso, en un sitio
  de docs el menu lateral se come el limite de caracteres: medido en
  `opencode.ai/docs/skills/`, los primeros 500 chars eran todos navegacion.
- `read` mira el **codigo HTTP**. Esto no es teorico: en un run real el modelo
  se invento `.../zod/master/docs.md`, recibio una 404 — que como texto son
  bytes perfectamente validos — y siguio como si hubiera leido la pagina. Ahora
  una 404 aborta con `No adivines otra URL: buscala con web.sh search`.
- La salida va truncada (`WEB_MAX_CHARS`, `WEB_READ_CHARS`): entra en el
  contexto del modelo.

### Por que SKILLS y no mas reglas

Una regla en `instructions` viaja **entera en cada turno**: knowledge-protocol
son 1231 tok/turno medidos. Una skill no: en el prompt solo va su `name` +
`description`, y el cuerpo entra **solo** cuando el modelo llama a la
herramienta `skill`. Es el sitio natural para el detalle largo que casi nunca
hace falta pero, cuando hace falta, hace falta entero.

```
skill/stop-and-verify/SKILL.md   cuando PARAR: las senales de que estas
                                 adivinando, que cuenta como prueba, la escalera
                                 de comprobaciones, el presupuesto, y como se
                                 redacta un "no pude verificarlo"
skill/web-research/SKILL.md      como buscar de verdad: los comandos de aqui,
                                 como se formula la query, que fuente vale
                                 (docs oficiales > changelog > issue con fecha >
                                 blog), cuanto leer, y por que ya no hay a quien
                                 delegar (su §5)
```

La regla siempre-activa se quedo como **disparador**: su escalon 6 ahora apunta
a `web.sh` y nombra las dos skills. El detalle vive en las skills.

### Tres cosas que rompen las skills en silencio

1. **`"skill": "allow"` en `permission`.** Sin eso no se cargan. La herramienta
   `skill` pide permiso con la accion `skill`, y cuando ninguna regla casa el
   binario devuelve `ask` (v1.18.19: `evaluate(...) ?? {action:"ask"}`); en
   `opencode run` un `ask` se **auto-rechaza**.
2. **El fichero se llama `SKILL.md` EXACTO**, dentro de `skill/<nombre>/`, y el
   `name:` del frontmatter debe coincidir con la carpeta. Campos aceptados:
   `name`, `description`, `license`, `compatibility`, `metadata`.
3. **No hay recarga en caliente.** Hay que salir de opencode y volver a entrar.

Comprobacion rapida de que opencode las ve:

```bash
opencode debug skill | python3 -c "import sys,json;[print('-',s['name']) for s in json.load(sys.stdin)]"
# - customize-opencode   (built-in)
# - stop-and-verify
# - web-research
```

### Efecto colateral que hubo que arreglar: `/tmp` estaba prohibido

En la prueba end-to-end ("¿como se marca un campo opcional en zod v4? no lo
supongas"), el modelo hizo lo correcto — `docs.sh npm zod`, bajarse el tarball,
descomprimirlo — y ahi se estrello:

```
! permission requested: external_directory (/tmp/zod_unpack/package/*); auto-rejecting
✗ Grep "optional(" failed
```

Leer fuera del proyecto cae en `external_directory`, que por defecto es `ask`, y
en modo no interactivo eso es un `no`. Se abre **solo el temporal**
(`/tmp/**`, `/private/tmp/**`, `/var/folders/**`; en macOS `/tmp` es un symlink
a `/private/tmp` y el permiso ve la ruta ya resuelta, por eso van los dos). Todo
lo demas sigue en `ask`. Verificado despues: `read /tmp/probe_ext_dir.txt` pasa
sin pedir nada.

### Estado de las pruebas

- `web.sh search` (Exa), `WEB_ENGINE=ddg` (respaldo) y `web.sh read`: ✅
- 404 en `read`: aborta con mensaje accionable ✅
- `opencode debug skill` lista las dos skills ✅
- El modelo carga una skill por su nombre y responde con su contenido ✅
- Pregunta que exige verificar (zod v4): el modelo **no adivino** — uso
  `docs.sh`, se bajo el paquete y contesto citando la fuente ✅
- Que cargue `web-research` **por su cuenta** al llegar al escalon web: ✅ visto
  con qwen3.5-9b-mtp. Traza real, tras chocar con el guard de comandos:
  `✗ ripgrep ... BLOCKED` → `→ Skill "web-research"` → `web.sh search "ripgrep
  limit results per file flag"` → responde `-m, --max-count` citando
  `man.archlinux.org/man/rg.1`. Con gpt-oss no llego a abrirla (acerto igual,
  pero yendo directo a los comandos).

## 🧭 `plugin/ground-truth.ts`: el estado real, cada turno

Las reglas le dicen al modelo "re-lee `.agent_progress.md`"… si se acuerda.
Esto no depende de que se acuerde: inyecta en cada peticion un bloque corto con

- `git status --short` (que has tocado ya), y
- **solo** la seccion `# VERIFIED FACTS` del fichero de progreso (lo que ya te
  costo un lookup y no hay que volver a mirar).

Si el repo esta limpio y no hay facts, **no inyecta nada** — no gasta tokens por
gastar. Maximo 12 lineas / 1.200 caracteres. Kill switch: `OPENCODE_GROUND_OFF=1`.

**Donde se inyecta importa:** al final (ultimo mensaje), NO en el system prompt.
El system prompt es el prefijo estable de la peticion; meterle contenido que
cambia cada turno invalidaria cualquier reuso de KV cache del servidor y pagarias
el prefill entero otra vez.

## 🧾 Balance de tokens (medido, no estimado)

Ablacion sobre una MISMA peticion, leyendo `usage.prompt_tokens` que devuelve el
propio LM Studio:

| Cambio                                   | Efecto por turno |
| ---------------------------------------- | ---------------- |
| Quitar el servidor MCP (roto)            | **−197 tok**     |
| Recortar reglas que ahora impone el guard| **−87 tok**      |
| Recortar la descripcion de `bash`        | **−1.004 tok**   |
| Quitar `todowrite`                       | **−477 tok**     |
| Desactivar los subagentes `explore`/`general` | **−129 tok** |
| `anti-slop-guard` + `ground-truth` + `slim-tools` | **0 tok** (son hooks) |
| **Total**                                | **≈ −1.900 tok** |
| (contexto: knowledge-protocol cuesta     | +1.231 tok)      |

Medido de punta a punta sobre el esquema de herramientas:
**3.773 → 2.411 tok** (−1.362 solo en esquemas).

Y no es solo contexto: el prompt fijo se **re-procesa en cada prefill**, asi que
cada token que quitas de aqui se nota tambien en la latencia de CADA turno.

## 🎫 `agent/ticket.md` — Historias de Usuario para Jira

Un agente primario (Tab) que redacta Historias de Usuario en sintaxis Jira Text.
No programa: es otro **modo de trabajo**, no una tarea dentro del de codigo.

### De agente a skill (y por que la decision se dio la vuelta)

Nacio como **agente** (`agent/ticket.md`) y hoy es la skill `jira-ticket`. La
razon original sigue siendo cierta en lo que decia, asi que se deja escrita:

| | Coste |
| --- | --- |
| **Skill** | El nombre + la descripcion van en el system prompt de **todos** los agentes, en **todos** los turnos. `auto` paga por una skill de tickets aunque este escribiendo Go. |
| **Agente** | Su prompt se carga **solo cuando el agente esta activo**. Coste para `auto`: **cero**. |

Lo que cambio no son los numeros, es lo que se pesa contra ellos. Pedir un
ticket como agente obliga a **cambiar de agente con Tab**, y eso significa
empezar de cero: el agente de tickets no ve el repo que acabas de estar mirando
ni la conversacion en la que descubriste el endpoint. Como skill, el ticket se
escribe **en la sesion donde ya estas**, con ese contexto delante — que es justo
lo que hace que la seccion de Notas Tecnicas cite rutas reales en vez de
`[POR CONFIRMAR]`.

El otro argumento original —"un subagente no puede conversar, por eso es
primary"— **no aplica a una skill**: una skill no es un subagente, se carga
dentro del agente primario que ya esta hablando contigo. El PASO 1 (preguntar y
esperar) sigue funcionando igual.

**Lo que se pierde, dicho sin adornos.** Un agente puede fijar cosas que una
skill no:

| Lo que hacia el agente | Como queda en la skill |
| --- | --- |
| `tools: {write: false, edit: false, bash: false}` | Texto: *"Write no files. The deliverable is the text block in the chat"* |
| `skill: false` (llamo a `customize-opencode` en mitad de un ticket) | Texto: *"Do not load another skill to write a ticket"* |
| `webfetch/duckduckgo_search: false` (once busquedas seguidas por un endpoint interno) | Texto: *"No search engine knows this company's endpoints"* |
| `temperature: 0.7` para redaccion | Hereda la de `auto` (0.6) |
| `permission: {edit: deny}` | Nada. `auto` tiene `edit: allow` |

O sea: tres restricciones que se pusieron **porque se vio fallar al modelo** pasan
de estar impuestas a estar pedidas. Es un cambio real de garantias, y por eso van
al principio del cuerpo de la skill, no enterradas al final.

**Un detalle que habria sido un bug feo:** el cuerpo del agente empezaba con la
linea `NON-CODING AGENT: skip engineering rules`, que es la marca que
`slim-tools` busca para borrar las reglas de codigo del system prompt. Al
convertir, esa linea **no** se copio. Si se hubiera copiado y el texto de la
skill acabara en el system prompt, `auto` se quedaria sin
`engineering-discipline` ni `knowledge-protocol` cada vez que alguien pide un
ticket.

Lo que **si** sobrevive intacto es `plugin/ticket-format.ts`: nunca estuvo atado
al agente —mira la salida de todos y solo toca texto que es inequivocamente un
ticket (`h3. Titulo:` + tres cabeceras numeradas)— asi que sigue renumerando
igual.

### El ticket ahora es un fichero, y de ahi va a Jira

Segunda iteracion, a peticion del usuario: el ticket ya no se queda en el chat.

1. La skill lo escribe en **`ticket-<descripcion-corta>.md`** en la carpeta
   actual (slug de 3-5 palabras sacado del titulo, sin acentos).
2. El usuario lo **lee y lo corrige a mano** si hace falta.
3. Cuando lo confirma, la skill lo crea en Jira con el MCP.

El fichero lleva **solo** el markup de Jira: sin fence, sin cabeceras de
Markdown, sin explicaciones. Tiene que poder pegarse en Jira tal cual, y es
literalmente lo que se manda por la API en el paso 3. En el chat quedan tres
lineas: donde esta el fichero, que quedo `[POR CONFIRMAR]`, y "dime si lo creo
en Jira".

#### El MCP tenia herramientas que el README no sabia (dos veces)

El comentario del config decia *"expone 5 herramientas"*. Un `tools/list` dijo
**6**. Y al leer el registro real del servidor
(`mcp-jira/mcp/src/mcp/factory.ts`, que las importa una a una) son **12**:

| herramienta | parametros |
| --- | --- |
| `jira-search` | consulta JQL |
| `jira-ticket-details` | `ticketId` |
| **`jira-create-ticket`** | **`projectKey`\*, `summary`\*, `description`, `issuetype`, `priority`, `assignee`, `labels`** |
| `jira-update-ticket` | edicion de campos |
| `jira-transition-ticket` | cambio de estado |
| `jira-add-comment` | comentario |
| `jira-create-meta` | issuetypes y campos que acepta un proyecto |
| `confluence-search` | `query`, `limit` |
| `confluence-read` | `pageId` |
| `confluence-write` | `pageId`\*, `body`\*, `title` |
| `confluence-create-page` | pagina nueva |
| `confluence-database-rows` | `database`\*, `limit`, `includeHtml` |

**La leccion no es el numero, es el metodo.** 5 → 6 → 12: las dos primeras
cifras venian de fotografiar el servidor un dia concreto, y el servidor siguio
creciendo. La fuente que no caduca es el codigo que registra las herramientas,
o `opencode mcp list` en el momento de usarlas.

Dos correcciones mas que salieron de leer el `inputSchema` de verdad:

- El nombre es **`jira-create-ticket`**, no `jira-ticket-create`. En la lista de
  herramientas del agente sale como `jiraAdmin_jira-create-ticket`: ese prefijo
  lo pone opencode, no es parte del nombre.
- **`parent` no existe.** Existen `assignee` y `labels`, que no estaban. El
  default de `issuetype` es `Task` (`DEFAULT_ISSUE_TYPE` en el fuente).

Sin esa comprobacion, el paso 3 se habria escrito contra una herramienta
inventada. La documentacion vieja mentia por omision, que es la forma mas comoda
de mentir.

#### Sin esto, el renumerado se perdia por el camino

`ticket-format.ts` arreglaba la numeracion `1..6` en el **texto del chat**
(`experimental.text.complete`). Al mover el ticket a un fichero, ese hook ya no
lo veia: el chat quedaba bien y el fichero —el que se lee y el que acaba en
Jira— se quedaba con el `h3. 5.` duplicado.

Ahora la misma regla se aplica tambien en `tool.execute.before` sobre `write` y
`edit`. Con un matiz que importa: en un `edit` solo se renumera si su
`newString` es el ticket **completo** (lleva `h3. Titulo:`). Renumerar un
fragmento desde 1 convertiria la seccion 5 en la 1 — el remedio peor que la
enfermedad. Tres tests nuevos cubren los tres casos.

#### La prueba: dos intentos, y el primero fallo de forma util

**Primer run:** cargo la skill, redacto el ticket... y **no aparecio ningun
fichero**. Lo que hizo, segun la traza:

```
✗ Write /Users/jaencarlos-Documents-personal-dotfiles/.../ticket-....md failed
$ cat > /Users/jaencarlos-Documents-personal-dotfiles/.../ticket-....md << 'EOF'
  zsh:1: no such file or directory
$ cat > "/Users/jaencarlos/Documents/personal-dotfiles/.../ticket-....md" << 'EOF'
  zsh:1: no such file or directory
```

Reconstruyo la ruta absoluta del proyecto **de memoria** y la corrompio dos
veces —se comio las barras: `jaencarlos-Documents-personal-dotfiles`— y despues
de fallar dos veces le dijo al usuario que el fichero estaba listo. El fallo no
es el error de ruta: es que **narro** el resultado en vez de comprobarlo.

Arreglo, dos lineas en la skill:

- **Ruta relativa pelada**: `write filePath: "ticket-xxx.md"`, sin directorio y
  sin ruta absoluta. Una ruta que no se escribe no se puede corromper. (Y de
  paso: un `cat > … << EOF` se salta el renumerado, que solo ve `write`/`edit`.)
- **Punto 8 del repaso final**: *"¿la herramienta `write` devolvio OK? Si no la
  llamaste o fallo, no hay fichero — dilo. Nunca escribas 'he escrito el ticket
  en...' de un fichero que no existe."*

**Segundo run**, mismo prompt:

```
← Write ticket-filtrar-facturas-fecha-estado.md
  Wrote file successfully.

He escrito el ticket en `ticket-filtrar-facturas-fecha-estado.md`.
Pendiente de confirmar: el endpoint del listado de facturas y los estados disponibles en backend.
Cuando lo revises, dime si lo creo en Jira.
```

El fichero: markup de Jira puro, cero fences, cero `##`, secciones 1..6 sin
repetir, seccion 6 literal, dos `[POR CONFIRMAR]` y ni una mencion a un stack
que nadie dijo. Y el ticket **no** se repitio en el chat.

#### 201 llamadas a la misma tool del MCP: el loop-breaker miraba donde no era

Con el fichero ya escrito, la segunda mitad del flujo: *"créalo en Jira,
proyecto FAC"*. Desde este Mac el servidor MCP **no es alcanzable** (el config
apunta a `localhost:9001` a proposito, porque normalmente opencode corre en la
misma maquina que el servidor). Resultado del primer intento:

- **201 llamadas** a `jiraAdmin_jira-ticket-create` en un solo run.
- Respuesta final en **ingles**, especulando: *"¿puedes verificar si se creo el
  ticket a pesar de los fallos?"*.

El loop-breaker no lo vio, por dos motivos que habia que arreglar los dos:

1. **Solo miraba `bash`.** Una tool de MCP no es bash.
2. La regla era *"misma salida identica dos veces"*, y **cuando una tool falla
   puede no llegar a `tool.execute.after`** — sin salida registrada, el contador
   de repeticiones no subia nunca y el bucle era invisible.

Ahora se cuentan **intentos** en el `before`: tres llamadas identicas a la misma
herramienta con los mismos argumentos son un bucle, devuelvan algo o revienten.
`skill`, `question` y `todowrite` quedan exentas a proposito — cargar dos veces
la misma skill es ruido, no un bucle, y bloquearlo dejaria al modelo sin su
procedimiento justo cuando lo necesita.

Mismo prompt, con el guard puesto:

| | antes | despues |
| --- | --- | --- |
| llamadas a `jira-ticket-create` | **201** | 8 menciones, ninguna en bucle |
| bloqueos necesarios | — | 0: paro solo |
| final | "verifica tu si se creo" | *"no puedo crearlo: la tool no esta accesible. Puedes copiar el contenido de `ticket-....md` y crearlo en FAC tu mismo"* |

Y lo importante: **no se invento un id de ticket**.

**Lo que sigue mal, dicho tal cual:** contesto en ingles. La regla de idioma de
la skill es explicita y la cumple mientras sigue el guion; cuando se sale por la
rama de error, se le olvida. Es un fallo de un 9B que no se arregla con mas
prompt — y no hay forma de imponerlo por hook.

**Lo que NO esta probado:** el camino feliz del PASO 3. Desde esta maquina el
servidor no responde, asi que se verifico que **falla con dignidad**, no que
crea el ticket. En la maquina donde corre el MCP (`localhost:9001`) es donde hay
que probarlo de verdad.

### Coste real de la conversion, y como quedo la prueba

Medido igual que el resto, con el `input` del server:

| | prompt fijo |
| --- | --- |
| 9 skills | 10537 tok |
| **10 skills (con `jira-ticket`)** | **10720 tok** — la skill de tickets cuesta **+183 tok/turno** |

Esos 183 los paga ahora `auto` siempre, tambien cuando escribe Go. Como agente
eran 0. A cambio, pedir un ticket ya no obliga a cambiar de sesion.

**La prueba en vivo** (peticion en español desde `auto`, sin tocar Tab): pidiendo
un ticket de "filtrar facturas por rango de fechas y estado, con error y
reintento".

- Abrio `jira-ticket` y **ninguna otra skill** — la restriccion que antes era
  `skill: false` aguanto siendo solo texto.
- **No creo ningun fichero** — igual con `write`/`edit` disponibles.
- Seis secciones numeradas 1..6 sin repetir, seccion 6 literal, sintaxis Jira
  (ni un `##` ni un `**`), todo en español, siete escenarios Gherkin incluyendo
  el de error y el de reintento.
- Y lo que no sabia fue a `[POR CONFIRMAR]` (endpoint, estados del backend,
  componente de UI) en vez de inventarse un stack: **cero** menciones a React,
  axios, `router.push` o `authToken`.

Es una sola prueba, con `auto` en `temperature: 0.6` en vez del 0.7 que tenia el
agente. Si con uso real los escenarios empiezan a salir calcados, la causa mas
probable es esa temperatura — y no hay forma de fijarla desde una skill.

### Decisiones que vienen del agente

- **Solo lectura** (`grep`/`read`/`glob`, sin `write`/`edit`/`bash`). No es por
  tokens: un ticket que cita el endpoint REAL vale mucho mas que uno generico.
  En las pruebas busca el endpoint antes de escribir. Y sin `write` no hay forma
  de que "ayude" creando ficheros.
- **`skill: false`** — en una prueba llamo a `customize-opencode` en mitad de un
  ticket. Turno tirado.
- **Regla anti-invencion explicita.** Es el fallo mas caro de un ticket: si dice
  "consumir `GET /api/v2/users`" y no existe, alguien pierde medio dia. Lo que
  no sepa va como `[POR CONFIRMAR]`.
- **`temperature: 0.4`** (vs 0.1 en `auto`): esto es redaccion, hace falta algo
  de variedad para que los escenarios no salgan calcados.

### Las reglas de codigo NO se pueden desactivar por agente

`instructions` en `opencode.jsonc` es **global**, y `AgentConfig` **no tiene
campo `instructions`** (verificado contra `https://opencode.ai/config.json`).
Medido en el agente `ticket`: de sus **5.558 tokens de prompt fijo, 3.070 (el
55%)** eran `engineering-discipline` + `knowledge-protocol` — "grep antes de
escribir", la escalera de lookups... para un agente que no toca codigo.

Lo resuelve `slim-tools.ts` con `experimental.chat.system.transform`: si el
prompt del agente lleva la linea `NON-CODING AGENT: skip engineering rules`, se
le borran las reglas. Sirve para cualquier agente futuro que no programe.
Verificado en el wire: **17.206 → 6.238 chars**, con el prompt del ticket intacto.

### ⚠️ Como ese mismo hook rompio el agente (y como se arreglo)

La v1 borraba por regex sobre cada entrada de `output.system`:

```js
if (/^#\s*(Engineering discipline|Knowledge protocol)/m.test(sys[i])) sys[i] = ""
```

opencode manda el system prompt **entero en UNA sola string** (17.206 chars:
prompt del agente + reglas + skills). Con la flag `m` el patron casaba **dentro**
de esa string y se blanqueaba ENTERA. Resultado medido en el trafico:
`system: 1 mensaje, 0 chars`. El agente, sin instrucciones, se invento un
formato de ticket completo — con tablas, emojis y un ID `#2026-08-31-LogoutUI`
inventado.

**El test unitario pasaba** (24/24) porque su fixture era un array de strings
separadas: una forma que no existe en la practica. Mismo patron que el bug de
`\Z`: el fixture equivocado hace que el test no pruebe nada.

Arreglo, en tres partes:

1. **Borrado LITERAL, no regex**: el plugin lee los ficheros de reglas de disco
   y elimina su contenido exacto. Si no aparece tal cual, no toca nada.
2. **Red de seguridad**: si un recorte dejaria el system con menos de 200
   chars, se descarta y se conserva el original.
3. **Tests con la forma REAL** (una string combinada montada desde los ficheros
   de reglas de verdad), que ademas comprueban que el prompt del agente
   **sobrevive**. Ese test falla contra la v1, que es justo el objetivo.

### Calidad de salida: honestamente, variable

Con input completo genera Jira valido: 6 secciones, Gherkin con camino feliz y
caso de error, y el endpoint real. Con input vago **pregunta en vez de
inventarse el endpoint**, que es el comportamiento que se buscaba.

La salida **varia entre ejecuciones** con el mismo input. Defectos observados en
runs distintos, y como se corrigio cada uno:

| Defecto observado | Arreglo |
| ----------------- | ------- |
| `DoH` en vez de `DoD` | prompt (encabezados fijos) ✅ |
| Reescribir la seccion 6 a su gusto | prompt (es texto literal) ✅ |
| Etiquetar el bloque como ```markdown | prompt ✅ |
| Saltarse la linea `h3. Titulo:` | prompt (lista de auto-repaso) ✅ |
| Llamar a la skill `customize-opencode` | `skill: false` ✅ |
| **Numerar dos veces la seccion 5** | **`plugin/ticket-format.ts`** — el prompt NO lo arreglaba |
| Inventar `router.push` / `authToken` / React | prompt (regla anti-invencion) ✅ |

El de la numeracion merece explicacion: se intento por prompt (una lista de
auto-repaso con los errores reales) y **no se corrigio**. Es un fallo mecanico,
de los que un modelo pequeño no ve al releerse. Numerar 1..6 en orden es una
invariante, no una opinion — asi que lo hace un hook (`experimental.text.complete`),
a coste cero y siempre bien, en vez de gastar mas prompt pidiendolo. Mismo
principio que `anti-slop-guard`: lo que se pueda imponer, no se pide.

Ultima ejecucion, con todo aplicado: 6 secciones numeradas 1-6, titulo, DoD,
seccion 6 literal, 2 escenarios Gherkin, endpoint real y sin stack inventado.

Aun asi: una plantilla de 6 secciones esta cerca del techo de un 20B. **Revisa
la seccion 5 antes de pegar en Jira** — es donde se colarian los nombres
inventados si el modelo se despista.

## 🐘 Lo mas caro del prompt no eran las reglas: eran las HERRAMIENTAS

Durante dos dias se optimizaron las reglas. Estaba mirando al sitio equivocado.
Midiendo el payload real (`usage.prompt_tokens` del propio LM Studio):

```
prompt fijo ......................... 9517 tok
sin NINGUNA herramienta ............. 5744 tok
=> los esquemas de tools cuestan .... 3773 tok  (39% del prompt fijo)
```

Y repartido de forma absurda:

| tool        | esquema | solo la descripcion |
| ----------- | ------: | ------------------: |
| `bash`      | 5353 B  | **4671 B**          |
| `task`      | 4087 B  | 3208 B              |
| `todowrite` | 2728 B  | 2012 B              |
| resto (6)   | 7861 B  | —                   |

La descripcion de `bash` sola pesaba mas que las de `edit`+`read`+`grep`+`glob`+
`write`+`skill` juntas.

### Que se hizo

- **`plugin/slim-tools.ts`** reescribe la descripcion de `bash` via el hook
  `tool.definition`: **4671 → 1167 chars**. NO es un truncado a lo bruto (cortar
  a 200 chars ahorraba mas, pero se llevaba por delante reglas que importan).
  Conserva `workdir` en vez de `cd`, comillas en rutas con espacios, el
  `timeout`, que la salida larga se guarda en fichero, preferir las tools
  dedicadas sobre `find`/`cat`/`sed`, y las reglas de git. Los datos que dependen
  del entorno (SO, directorio temporal, los limites 400/16000 que son VUESTROS)
  se extraen del texto original, no se hardcodean. Kill switch: `OPENCODE_SLIM_OFF=1`.
- **`todowrite: false`** en `auto`: competia con `.agent_progress.md`, que ademas
  sobrevive a la compactacion porque esta en disco. Dos mecanismos para lo mismo
  solo dividen la atencion de un modelo pequeño.
- **`explore` y `general` desactivados**: la descripcion de `task` ENUMERA los
  subagentes disponibles, asi que cada uno se paga en cada turno. Quedo solo
  `analyze` — y el 2026-09-07 tambien se fue, con `task` detras.

### Validacion de comportamiento (no solo de tokens)

Contar tokens no prueba nada: recortar la descripcion de una herramienta puede
hacer que el modelo la use mal. Prueba real con la descripcion recortada — bug
de `Truncate()` contando bytes en vez de runas, con test de Go:

```
Edit  strutil.go   → utf8.RuneCountInString(...)   (sin el import: no compila)
Edit  strutil.go   → []rune(s)                     (se corrige solo)
Bash  go test ./...
ok  	strutil	0.580s
```

Arreglado y verde. **Es UN caso, no un benchmark**: vuestro propio README avisa
de que un solo sample no vale para concluir. Para estar seguros, pasad las dos
tareas de `Chunk()`/`Truncate()` con `OPENCODE_SLIM_OFF=1` y sin el.

## ✅ Validacion de los cambios: benchmark con tests OCULTOS

Misma metodologia que el benchmark de gpt-oss: dos tareas de Go puntuadas con
`go test` contra tests que **el agente nunca ve**, mas una funcion extra en cada
fichero (`Sum`, `Repeat`) que el agente no debe tocar — si la borra, el test lo
caza.

- **`Chunk()`** — la solucion ingenua `s[i:j]` COMPARTE memoria con la entrada y
  falla; ademas `n <= 0` debe devolver `nil`.
- **`Truncate()`** — la doc dice runas, el codigo cuenta bytes.

Condiciones: `on` = config de hoy; `off` = los tres plugins desactivados
(`OPENCODE_SLIM_OFF=1 OPENCODE_GUARD_OFF=1 OPENCODE_GROUND_OFF=1`).

| tarea      | condicion | resultado | tiempo |
| ---------- | --------- | --------- | ------ |
| `Chunk()`  | on        | **PASS**  | 46 s   |
| `Chunk()`  | off       | **PASS**  | 33 s   |
| `Truncate()`| on       | **PASS**  | 50 s   |
| `Truncate()`| off      | **PASS**  | 36 s   |

**4/4 en ambas condiciones, 0 funciones borradas** (los tests `TestSumSurvives` /
`TestRepeatSurvives` pasan). Ni un bloqueo del guard ni un aviso falso en los
cuatro runs: **los plugins no estorban**.

Dos honestidades sobre esta tabla:

1. **`off` NO es "la config de antes".** Solo apaga los plugins; las reglas
   (`knowledge-protocol`, +1.231 tok) y los cambios de config (`todowrite`
   fuera, subagentes desactivados) siguen activos en ambas columnas. Esto valida
   los plugins, no el conjunto entero.
2. **Los tiempos no concluyen nada.** `on` sale 13-14 s mas lento, pero son
   DOS muestras por condicion y el reloj incluye la varianza de LM Studio. Con
   `n=2` no se puede afirmar que los plugins cuesten tiempo — igual que vuestra
   propia correccion sobre el 9B ("un solo sample no vale"). De uno de esos 14 s
   si se conoce la causa (abajo); del resto, no.

### Un defecto REAL que encontro el benchmark

En `run-chunk-on` aparecio esto:

```
! permission requested: external_directory (~/.config/opencode/*); auto-rejecting
✗ Read ~/.config/opencode/... failed
```

El modelo intento **LEER** `~/.config/opencode/bin/docs.sh` con la herramienta
`read` en vez de ejecutarlo. Como cae fuera del proyecto, salta el permiso
`external_directory`, que en modo no interactivo se auto-rechaza: **un turno
tirado**. La culpa era de la regla, que daba una ruta absoluta y parecia un
fichero que abrir.

Arreglado en la causa, no en el texto: el hook `shell.env` de `slim-tools` mete
`~/.config/opencode/bin` en el `PATH`, asi que la regla ahora es simplemente

```bash
docs.sh npm express      # run it, never read it
```

Sin rutas absolutas, mas corta, y sin nada que invite a abrir un fichero fuera
del proyecto.

## 🐞 Dos bugs que solo aparecieron al mirar el trafico real

Los tests unitarios pasaban (18/18) y el benchmark daba 4/4. Aun asi habia dos
bugs graves, y los dos salieron de mirar lo que el agente hace **de verdad**, no
lo que el prompt dice que deberia hacer.

### 1. El fichero de progreso cambio de sitio y los plugins no se enteraron

`agent/auto.md` pasó a usar `.agent/progress.md` (en un directorio gitignored,
mejor diseño). Pero `anti-slop-guard.ts` y `ground-truth.ts` seguian con la ruta
vieja `.agent_progress.md`. Consecuencias, ambas **verificadas ejecutando los
hooks**, no deducidas:

| | Efecto |
| --- | --- |
| `anti-slop-guard` | **BLOQUEABA el fichero de progreso en cada RESUME.** El agente lo lee con `cat` (bash), que NO cuenta como "leido" porque no pasa por la tool `read`; al reescribirlo, bloqueo. Rompia justo el protocolo de resume que este setup existe para sostener. |
| `ground-truth`    | **Nunca inyectaba los VERIFIED FACTS**, que son la mitad valiosa del plugin: buscaba un fichero que ya no se escribe. |

Arreglado aceptando las **dos** convenciones en ambos plugins, con tests de
regresion para cada caso. Verificado end-to-end con un escenario de RESUME real
(un `.agent/progress.md` ya existente, tarea a medias):

```
$ cat .agent/progress.md          ← lee el progreso
✱ Grep "a\.go" · 4 matches        ← busca antes de escribir (regla §1)
→ Read a.go
← Edit a.go                       ← EDITA, no reescribe
← Write .agent/progress.md        ← ESTO es lo que antes bloqueaba el guard
$ go build ./...                  ← verifica
$ git status --short              ← comprueba el arbol
```

0 bloqueos, `func A()` intacta junto a la nueva `func B()`, `FILES DONE`
actualizado y build en verde. Ademas el agente siguio la disciplina sin que
nadie se lo recordara: buscar antes de escribir, editar en vez de reescribir, y
verificar al final.

> Leccion: al renombrar algo que varios sitios conocen, `grep` la ruta vieja por
> TODO el repo. Aqui vivia en 2 plugins, 2 reglas y un comentario.

### 2. `\Z` no existe en JavaScript

`ground-truth` extraia la seccion de facts con:

```js
body.match(/^#+\s*VERIFIED FACTS\s*$([\s\S]*?)(?=^#\s|\Z)/m)
```

En JS **`\Z` no es "fin de cadena"** — es una "Z" literal. Asi que la seccion
solo se encontraba si venia OTRA cabecera detras. Si `# VERIFIED FACTS` era la
ultima seccion del fichero (el caso normal), devolvia vacio **en silencio**.

El test unitario original no lo detecto porque su fixture tenia un `# NEXT STEP`
detras. Ahora se extrae sin regex acrobatica (buscar la linea, cortar en la
siguiente cabecera o en EOF) y hay un test con la seccion al final.

### Lo que si funciona (verificado en el wire)

`ground-truth` inyecta correctamente, capturado con el proxy:

```
<repo-state note="injected automatically, always current">
uncommitted changes (git status --short):
 M a.go
?? .agent_progress.md

facts you already verified (do not look these up again):
- gin v1.12.0 es la ultima — source: docs.sh go
</repo-state>
```

## ⚠️ El agente NO crea el fichero de progreso en tareas cortas

En los 4 runs del benchmark, `.agent/progress.md` **no se creo ni una vez**, pese
a que `auto.md` §1 dice que es "the FIRST tool call of every task".

No es necesariamente un fallo del modelo: para una tarea de 45 segundos y 4
llamadas a herramientas, montar un fichero de progreso es desproporcionado — y a
un modelo pequeño, una instruccion desproporcionada le enseña a ignorar la
seccion entera, incluida la parte que si importa (el RESUME).

**Resuelto el 2026-09-11 con la primera opcion** (ver *`auto` vs `build`* mas
arriba): `auto.md` §2 dice ahora que el fichero es para tareas de mas de ~8
llamadas o mas de 2 ficheros, y que saltarselo en un arreglo de 4 llamadas es
lo correcto. Con la version anterior — "FIRST tool call of every task" — el
modelo SI lo creaba en el benchmark (2 turnos antes de leer una linea de
codigo) y luego lo reescribia entero al final: era la mitad de la ceremonia que
hacia a `auto` tardar 13 turnos donde `build` tardaba 5. Las dos opciones que
habia:

- **Hacerlo condicional** en el prompt ("si la tarea necesita mas de ~5 pasos o
  vas a tocar mas de 2 ficheros"). Honesto, pero sigue dependiendo de que el
  modelo lo cumpla.
- **Que lo cree un hook** (`chat.message`) con el GOAL literal del usuario. Cero
  tokens y deterministico — que es justo el patron que ya funciona aqui.

Nota: el valor de `ground-truth` esta acoplado a esto. Sin fichero de progreso
solo inyecta `git status`; los VERIFIED FACTS necesitan que alguien los escriba.

## 🔑 El deny de `.env` tenia un agujero: `bash`

Comprobado en vivo pidiendole al agente que leyera un `.env`:

```
Read .env failed — The user has specified a rule which prevents you...
```

O sea: `*.env` **si** casa con un `.env` pelado, el permiso `read` funciona.
Pero solo cubre la herramienta `read` — y `bash` esta en `"*": "allow"`, asi que
`cat .env` se lo saltaba entero. Taparlo con patrones de bash en el config es un
juego de topos (`less`, `head`, `xxd`, `awk`, redirecciones…), asi que lo hace
`anti-slop-guard` mirando el comando de verdad: si referencia un `.env` (no
`.env.example`) con un comando que lee ficheros, lo bloquea.

Honestamente: es *best-effort*, no una caja fuerte. Un `source .env && echo $X`
sigue siendo posible. Cubre el caso habitual, que es el accidente, no el ataque.

## ⚠️ Claves de `tools:` que no existen fallan EN SILENCIO

El comentario de `agent/analyze.md` avisaba de esto, y tenia razon: habia un
`patch: false` y **no existe ninguna herramienta `patch`**. Verificado con
`opencode debug agent analyze`: la clave se descarta y no aparece en la config
efectiva. Las que existen de verdad:

```
bash, edit, glob, grep, read, skill, task, todowrite, write   (+ webfetch)
```

Comprobalo siempre asi antes de fiarte de un `tools:`:

```bash
opencode debug agent auto | python3 -m json.tool | grep -A10 '"tools"'
```

## 🧯 Permisos: las formas SIN argumentos no casaban

`"git reset --hard *"` no casa con `git reset --hard` a secas — que es a la vez
comunisimo y destructivo. Lo mismo con `git push`, `sudo` y `rm -rf`. Ahora estan
las dos formas de cada uno. (El orden importa: opencode aplica la **ultima**
regla que casa, por eso lo general va primero.)

## 🧹 Defaults que estaban al azar

| Ajuste       | Ahora        | Por que |
| ------------ | ------------ | ------- |
| `autoupdate` | `"notify"`   | Este README documenta comportamiento sacado del binario de **v1.18.19**. Si se actualiza solo, deja de ser cierto sin avisar. |
| `share`      | `"disabled"` | Setup 100% local; no hay nada que compartir fuera. |
| `snapshot`   | `true`       | Red de seguridad para un agente autonomo que edita solo. |

### Como verificar la config sin gastar una llamada al modelo

`opencode debug config` imprime la configuracion YA resuelta (baseURL,
`instructions`, `mcp`, modelo). Es instantaneo y no toca el servidor — mucho
mejor que el `opencode run "sin usar herramientas…"` que se sugiere mas arriba:

```bash
opencode debug config | python3 -m json.tool | grep -A3 instructions
opencode debug agent auto      # config efectiva de un agente
opencode debug startup         # cuanto tarda en arrancar (aqui: ~470ms)
```

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

### Plugin de tokens/segundo

`plugin/tokens-per-second.ts` muestra un toast tras cada respuesta con los
tokens del mensaje (entrada→salida) y la velocidad:
`⚡ 48.3 tok/s · 1,234→320 tok · 🧠80 · 6.6s`. Para vigilar el server local: si
el número se desploma (de ~50 a ~15) suele ser que el KV cache se salió de la
VRAM y hay offload a CPU.

**Está DESACTIVADO por defecto** (opt-in). Para encenderlo, abre opencode con la
variable de entorno:

```bash
OPENCODE_TPS_ON=1 opencode        # o exporta la var en tu ~/.zshrc
```

Se dejó apagado porque el toast es transitorio (aparece ~8s y desaparece). El
plugin se conserva funcional; solo hay que poner la variable para reactivarlo.

### Superficies de la TUI: qué se puede y qué no (comprobado)

Un plugin de **hook** (fichero `.ts` local) solo puede mostrar información con
`client.tui.showToast` — el **toast**. El resto de `client.tui.*` (`appendPrompt`,
`publish`, …) no pinta texto fijo. La config nativa `tui` tampoco tiene opción
para añadir tokens al footer (`Auto · modelo · 13.1s` lo pinta opencode).

Las ubicaciones **persistentes** (panel lateral `sidebar_content`, junto al
prompt `session_prompt_right`, footer) existen como *slots*, pero son del
**sistema de plugins de TUI** (JSX + `@opentui/solid`), no de los hooks.
Probado: un `.tsx` local **no se carga** — esos slots solo los llenan plugins
internos o **paquetes npm**.

### Opción B — ubicación persistente (pendiente, si algún día se quiere)

Para poner los tokens/tok/s en un sitio fijo (lo ideal: `session_prompt_right`,
justo al lado de donde escribes), hay que construir un **paquete npm de plugin
TUI**, no un fichero suelto. Lo investigado deja el camino:

- **Export**: el módulo exporta `{ id, async tui(api) {…} }` (`TuiPluginModule`),
  no un `Plugin` de hooks.
- **Registro**: `api.slots.register({ order, slots: { session_prompt_right(_, p) { return <Comp .../> } } })`.
- **Render**: JSX de `@opentui/solid` con elementos `box` / `text` / `b`
  (mismo patrón que el plugin interno "Context").
- **Datos**: `api.state.session.messages(sessionID)` (último mensaje →
  `tokens{input,output,reasoning}`, `time{created,completed}`), leídos dentro de
  un `createMemo` para que sea reactivo.
- **Empaquetado**: directorio con `package.json` + dependencia `@opentui/solid`
  + build a `.js`, declarado en el array `plugin` de `opencode.jsonc`.
- **Aviso**: la API de plugins TUI **no está documentada** (sale solo de los
  type-defs `@opencode-ai/plugin/dist/tui.d.ts` y del binario) → puede cambiar
  sin previo aviso.

Honestidad sobre la medida: opencode solo expone timing a nivel de **mensaje**
(`created→completed`), que incluye el time-to-first-token y el tiempo de
ejecución de herramientas. **No es decode puro.** Por eso salta turnos triviales
(<40 tokens, donde el TTFT domina y engañaría) y se etiqueta como throughput del
turno. Para decode exacto: `make bench`. Los tokens de thinking se muestran
aparte (`🧠`), así ves el coste del razonamiento. Se apaga con
`OPENCODE_TPS_OFF=1`. Los toasts solo aparecen en la TUI (no en `opencode run`).

### 6. Thinking híbrido (auto sin thinking, analyze con thinking)

El bug de "respuesta vacía" **era de qwen3.5**: con thinking ON su bloque de
razonamiento se comía el presupuesto de `output` entero y devolvía `content`
vacío (medido: un `17*23` gastó los 300 tokens de output en `reasoning` y no
contestó). Y crecía con el prompt, así que empeoraba justo cuando la sesión se
alargaba.

**Con gpt-oss-20b ese bug no aparece.** Su razonamiento no crece sin control
con el tamaño del prompt.

Pero "no se desborda" **no** quiere decir "es gratis". Medido en tareas reales
(ver el benchmark objetivo más abajo), subir a `high` cuesta **5-7x más tiempo
para el mismo resultado**, porque en un bucle agéntico el razonamiento se paga
en CADA turno. Por eso:

```jsonc
// opencode.jsonc
"agent": { "auto": { "reasoningEffort": "low" } }    // <- clave TOP-LEVEL, camelCase
// agent/analyze.md (frontmatter)
reasoningEffort: medium
```

> ⚠️ **Cómo NO medir el razonamiento.** Una medición anterior decía que `high`
> "solo cuesta ~43 tokens". Estaba hecha con un `¿cuánto es 17*23?` de una sola
> vuelta, y llevó a poner `analyze` en `high`. Con prompts de 8k tokens y varios
> turnos el coste real se dispara. **Mide con la carga real, no con juguetes.**

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

> ⚠️ **El backend ya no es LM Studio: es llama-swap delante de llama.cpp**, en
> el mismo `http://pcgamer:1234`. Se comprueba en un segundo:
> `curl -s http://pcgamer:1234/v1/models | grep owned_by` → `"llama-swap"`.
> La clave del provider en `opencode.jsonc` se sigue llamando `lmstudio` para
> no tocar todas las referencias `lmstudio/...`: es un nombre heredado.

Los ids son los de la config de llama-swap, **no** rutas de HuggingFace.
`make models` los lista y además los contrasta con lo declarado:

| Modelo (id real) | Quant | n_ctx (`-c`) | Uso |
| --- | --- | --- | --- |
| **`qwen-35b`** | UD-IQ3_XXS | 49152 | **Principal** + `small_model` + los 2 agentes |
| **`qwen-9b`** | Q4_K_M (MTP) | sin verificar | Fallback declarado |
| **`gpt-oss-20b`** | MXFP4 | sin verificar | Fallback declarado |

`qwen-35b` es Qwen3.6 35B A3B: un MoE de 35B totales con ~3B activos por token.
Cabe en 12GB porque llama.cpp deja 16 capas de expertos en CPU y cuantiza el KV
cache. La línea de arranque real, tal cual la devuelve `curl -s
http://pcgamer:1234/running`:

```
-c 49152 -ngl 99 -np 1 -fa 1 --n-cpu-moe 16
--cache-type-k q4_0 --cache-type-v q4_0 -b 512 -ub 512
--spec-type draft-mtp --spec-draft-n-max 4
```

**Corrección de una fila que estuvo mal mucho tiempo:** este README decía
`qwen/qwen3.6-35b-a3b — Descartado: no carga (OOM)`. Era cierto **para el
Q4_K_M**. En UD-IQ3_XXS y con `--n-cpu-moe 16` sí carga, y va a 54.7 tok/s
medidos con `make bench`. Un "no se puede" sin la cuantización al lado no es un
hecho, es una foto de un intento.

### Tres cosas que cambiaron al pasar de LM Studio a llama-swap

1. **Un id inexistente ya no es silencioso.** LM Studio caía de vuelta al
   modelo cargado sin decir nada — de ahí el viejo aviso *"declarar un modelo
   que no está cargado no da error"*. llama-swap corta en seco:

   ```
   HTTP 404 {"error":{"message":"no router for requested model"}}
   ```

   Es mejor noticia de lo que parece (un id mal escrito ahora se ve), pero
   significa que una config desactualizada **no arranca**, no que "va peor".
   Esto ya pasó: `model`, `small_model` y los dos agentes apuntaban a
   `lmstudio/qwen3.5-9b-mtp`, que aquí no existe.

2. **No hay `/api/v0/*`.** Era propio de LM Studio. `make ctx` y `make bench`
   estaban rotos por eso y ahora usan lo que sí existe: `/running` (que expone
   la línea de comandos entera, `-c` incluido, sin cargar nada) y el objeto
   `timings` que llama.cpp mete en la respuesta OpenAI-compatible.

3. **`-np 1`: un solo slot.** Dos peticiones simultáneas se **serializan**.
   Delegar en el subagente `analyze` no paraleliza nada: hace cola detrás de
   `auto`. Sirve para no ensuciar el contexto del que llama, no para ir rápido.

### `reasoning_effort` con qwen-35b: sin efecto medible (todavía)

Misma pregunta de código (bug de concurrencia en Go: explicar, proponer el fix
y escribir el código final), mismo modelo, contando `usage.completion_tokens`:

| effort | completion_tokens | finish |
| --- | --- | --- |
| low | 8 010 | stop |
| low | **4 074** | stop |
| low | 6 265 | stop |
| medium | 11 171 | stop |
| high | **3 215** | stop |

**`high` (3 215) salió por debajo de los tres `low`, y entre los propios `low`
hay un factor 2** (4 074 vs 8 010). Con estas muestras el efecto del parámetro es
indistinguible del ruido: o el backend no lo propaga a este modelo, o la
varianza se lo come. La tabla de `low` vs `high` que
hay más arriba en este README es **de gpt-oss-20b** y no se ha reproducido aquí.

Lo que sí sale de aquí, y es lo que cambió la config:

- Un turno de coding real llega a **~11k tokens**, casi todos de razonamiento
  (en el de 11 171: ~9.5k en `reasoning_content`, ~800 de respuesta). El
  `output: 8000` que estaba declarado **truncaba ese turno a media frase de
  razonamiento**. Ahora es 14000.
- Ese margen se paga: `output` se resta del umbral de compactación
  (46000 − 14000 = **32000** tokens de conversación).
- Y el método: **no midas el razonamiento con una sola muestra.** Es el mismo
  error que ya está documentado más arriba con el `¿cuánto es 17*23?`, cometido
  otra vez en otra forma.

Y sigue valiendo lo de antes, ahora por una razón más fuerte: `small_model` y
los agentes apuntan **al mismo modelo** porque llama-swap solo mantiene uno
residente. Apuntar a otro no paga una carga: paga una descarga + una carga, y
otra vuelta en el turno siguiente.

## 🔁 Cambio de modelo principal: gpt-oss-20b → qwen3.5-9b-mtp

> 🕰️ **Sección histórica, ya superada.** El principal actual es `qwen-35b`
> (Qwen3.6 35B A3B) sobre llama-swap — ver *Modelos actualmente en pcgamer*.
> Se conserva porque el método de comparación sigue valiendo; los ids y los
> veredictos de aquí son de la época de LM Studio.

En su momento **todo** pasó a apuntar a `qwen3.5-9b-mtp`: `model`, `small_model`
y el `model:` de los agentes. Que todos lleven el mismo no es cosmético: el
servidor solo mantiene un modelo residente, así que un subagente con otro modelo
paga un swap completo (30-50 s) cada vez que `auto` delega.

### Lo medido antes de tocar nada

| | qwen3.5-9b-mtp | gpt-oss-20b |
| --- | --- | --- |
| Quant | Q4_K_M | MXFP4 |
| decode ("cuenta hasta 60") | **61.4 t/s** | 56.5 t/s |
| TTFT | 0.28 s | — |
| tool call | PASS a la primera, `{"city":"Madrid"}` | PASS (4/4) |
| `reasoning_effort` | aceptado, razona en `reasoning_content` | aceptado |
| n_ctx cargado | **65536** | 50176 |

Un 9B **denso** más rápido que un MoE de 21B suena raro hasta que miras la
variante: `mtp` es *multi-token prediction* — predice varios tokens por paso y
los verifica — y va en Q4_K_M, no en Q6_K. Cuidado con la fila
`qwen/qwen3.5-9b` (40.7 t/s) de la comparativa: **no es otro modelo**, es este
mismo peor cuantizado y sin MTP.

### Lo que el cambio gana en contexto

`n_ctx = 65536` (contra 50176) permite declarar `context: 62000` con ~3.5k de
colchón:

```
umbral = context - min(output, 32000) = 62000 - 16384 = 45616 tokens
```

frente a los **39808** de gpt-oss: casi 6k más de conversación antes de que
salte la compactación, que es justo donde se pierde el objetivo original.
`output: 16384` no es capricho — qwen3.5 razona, y el thinking sale del mismo
presupuesto: quedarse corto trunca la respuesta a mitad de razonamiento.

### `temperature` / `top_p`: se cambian con fuente, no a ojo

El 0.1 / 0.8 de antes venía de gpt-oss y su propio comentario decía
`DO NOT TRUST THIS VALUE`. La model card de Qwen publica los valores para
**este** modelo (<https://huggingface.co/Qwen/Qwen3.5-9B>, 2026-03-09):

| Modo | temp | top_p |
| --- | --- | --- |
| Thinking, tareas de código precisas | 0.6 | 0.95 |
| Thinking, tareas generales | 1.0 | 0.95 |
| Instruct (sin thinking), general | 0.7 | 0.8 |

Así queda: `auto` y `analyze` con **0.6 / 0.95** (el preset de código), `ticket`
con **0.7 / 0.95** — escribe texto, necesita algo más de variedad léxica, pero
el formato del ticket no admite riesgos. `top_k` y `min_p` **no** se ponen en el
frontmatter: opencode solo documenta `temperature` y `top_p`, y una clave
desconocida se cuela en `options` sin dar error. Si los quieres, van en la
configuración de carga de LM Studio.

Encontrar esos valores fue, literalmente, el primer uso serio de `web.sh`:
una búsqueda, la model card oficial, valores citados. Antes de esto la
alternativa era inventárselos.

### Sigue SIN medir con este modelo

Se hereda de gpt-oss y está anotado como pendiente en el config, no como verdad:

- El benchmark objetivo de código con tests ocultos (2 tareas, `go test`).
- `reasoningEffort: low` — se mantiene porque el argumento de fondo (el
  razonamiento se regenera en CADA turno del bucle) no depende del modelo.
- El coste en tokens del prompt fijo, que cambia con otro tokenizer.

## 🔄 El bucle de 229 pasos: nada en opencode lo paraba

Primer run end-to-end tras cambiar a qwen. La pregunta era trivial ("¿cómo se
marca un campo opcional en zod v4?"). A los **20 minutos** seguía corriendo. El
log lo contaba todo:

```
step=227 ... agent=analyze mode=subagent
  evaluated permission=bash pattern="webfetch \"https://raw.githubusercontent.com/.../changelog.mdx\" 2>/dev/null"
step=228 ... (idéntico)
step=229 ... (idéntico)
```

`webfetch` es una **herramienta** de opencode, no un comando de shell. El
subagente la escribió en `bash`. Y el fallo se hizo invisible solo:

1. `bash` responde `command not found` → **por stderr**.
2. El propio modelo había puesto `2>/dev/null` en su comando.
3. Lo que quedaba era `... | grep -i optional | head -10` → **salida vacía**.
4. El modelo lee "no hay resultados", vuelve a intentarlo… exactamente igual.

Un error convertido en "sin resultados" es la receta perfecta de un bucle: el
modelo nunca se entera de que la herramienta no existe. Corría desde hacía 20
minutos y hubo que matarlo a mano.

### Por qué no lo cortó nada

- `doom_loop`, que suena a esto, **no es esto**: en el binario está atado a
  reintentar el *formatter* tras fallos repetidos, no a detectar tool calls
  repetidas.
- El tope de iteraciones existe pero **no estaba puesto**. Es `steps` en el
  frontmatter del agente: *"maximum number of agentic iterations before forcing
  text-only response"* — al llegar, deshabilita las herramientas y obliga a
  responder con texto.

### Los dos arreglos (los dos de entorno, cero prompt)

**1. Tope de iteraciones.** `analyze: steps: 15` (contesta UNA pregunta concreta;
más que eso no es investigar, es girar en redondo) y `auto: steps: 120` (red de
seguridad, no presupuesto: no debe morder en trabajo normal).

**2. `bin/webfetch` y `bin/websearch`.** Si el modelo escribe el nombre de una
herramienta en bash, que **funcione**: son alias de `web.sh read` y
`web.sh search`. Se puede discutir si esto tapa el error del modelo; lo que no se
discute es el resultado — la primera llamada devuelve la página y el bucle no
llega a existir.

**3. El guard de comandos inexistentes** (`plugin/anti-slop-guard.ts`). Los dos
anteriores tapan dos nombres concretos; esto ataca la causa. Antes de ejecutar,
mira la primera palabra de cada tramo del comando y, si `command -v` no la
resuelve, **aborta con un error de verdad** en vez de dejar que bash lo escupa
por stderr y el modelo se lo trague:

```
BLOCKED: `ripgrep` is not a command on this machine (checked with `command -v`).
It did NOT return an empty result — it does not exist. Do not run it again, and
do not hide the error with `2>/dev/null` or a `| grep`: that turns "command not
found" into silence and you will loop. ...
To search the web from bash: `web.sh search "..."` ...
```

Salta tramos separados por `|`, `&&`, `;`; ignora rutas, `$VAR`, `$( )`,
asignaciones (`FOO=1 cmd`) y palabras clave del shell; mira detrás de `sudo`,
`env`, `xargs`. Y usa el PATH **con el bin de opencode añadido**: sin eso
bloquearía `web.sh` y `docs.sh`, que es justo lo que queremos que use. Ante la
duda no bloquea — un falso positivo aquí para al agente en seco. Cubierto por
tres tests nuevos en `test/plugins.mjs` (34 pass).

### La prueba que antes se colgaba

Misma pregunta que provocó el bucle de `ripgrep`, ya con los tres arreglos:

```
✗ ripgrep --help 2>&1 | grep -iE "limit|max|count|file" | head -20 failed
  Error: BLOCKED: `ripgrep` is not a command on this machine ...
→ Skill "web-research"
$ web.sh search "ripgrep limit results per file flag"
  -> -m, --max-count NUM: Limit the number of matching lines per file searched

La flag es **`-m`** / **`--max-count NUM`**.
Fuente: https://man.archlinux.org/man/rg.1
```

El error accionable no solo rompió el bucle: el modelo **abrió la skill
`web-research` por su cuenta**, que era justo lo que quedaba por ver.

### El run de después

Mismo prompt, misma máquina, con los arreglos puestos:

```
$ docs.sh npm zod | grep -i optional     -> (vacío)
$ grep -rn optional node_modules/zod/... -> (vacío)
⚙ duckduckgo_search                      -> (nada: el MCP roto, turno perdido)
$ web.sh search "zod v4 optional field method name"
  -> Title: Defining schemas | Zod   URL: https://zod.dev/api
     "## Optionals ... z.optional(z.literal("yoda")); // or z.literal("yoda").optional()"

**`.optional()`** — fuente: https://zod.dev/api (sección "Optionals")
```

La escalera funcionó de arriba abajo y la respuesta viene **con fuente**. Ese
turno tirado en `duckduckgo_search` es lo que acabó de decidir apagar ese MCP
(sigue devolviendo `202 Ratelimit`, verificado por stdio el mismo día).

## 🌀 Seguía atascándose: la regla del prompt no basta, el hook sí

Reporte del usuario después de lo anterior: *"sigue quedando algunas veces en
loop… le pedí crear un proyecto nuevo y ha iterado muchas veces en lo mismo y no
se detiene a validar el error"*. Es exactamente lo que ya prohíbe el prompt de
`auto`:

> §3.4 **NO REPEATS** — if the same command fails twice, do not run it a third
> time.

Ahí está el problema de fondo de todo este directorio, otra vez: una regla del
prompt se cumple *casi siempre*; y "casi" con un bucle infinito significa que un
día te comes 229 pasos. El guard de comandos inexistentes solo cubría un caso
(`command not found`). Faltaba el general: **repetir algo que ya devolvió lo
mismo**.

### `plugin/loop-breaker.ts`

No bloquea "repetir". Bloquea **repetir sin información nueva**, que no es lo
mismo y la diferencia importa:

- Se guarda el **hash de la salida** de cada comando (`tool.execute.after`).
- Si un comando se ejecuta y devuelve **exactamente lo mismo** que la vez
  anterior, el tercer intento se corta.
- Un `edit`/`write` **borra el historial** de la sesión: el mundo cambió, el
  siguiente `go test ./...` no es una repetición.
- Si la salida **cambia**, no se corta nunca: `docker compose ps` esperando a
  que algo levante es legítimo.

Con **dos claves** por comando, porque el bucle real mutaba la tubería sin
cambiar nada de verdad:

| clave | qué agrupa |
| --- | --- |
| exacta | el comando entero normalizado |
| cabeza | lo anterior al primer `\|` — así `X \| grep max` y `X \| grep limit` cuentan como **el mismo intento**, que es lo que son |

Y el mensaje no dice "para", dice **qué hacer**, porque un modelo pequeño copia
lo que lee:

```
BLOCKED (loop): you already ran this exact command 2 times and the output was
IDENTICAL every time. Changing the `grep`/`head` after the pipe is NOT a
different attempt.
1. Run it ONCE with no filters — no `| grep`, no `| head`, no `2>/dev/null` —
   and read the FULL output. An error you filtered out looks exactly like an
   empty result.
2. Write the error's meaning in one sentence...
3. web.sh search "<paste the exact error line>"
4. Load the skill `unstick` for the full procedure.
```

### La otra forma de girar en redondo: sin repetirse

Un bucle no siempre repite el mismo comando. En un run real de "crea un proyecto
de Node", el proyecto estaba **hecho y funcionando en el paso ~20** y el modelo
gastó los **100 siguientes** en "verificar": `grep TODO`, `grep "^//"`,
`ls`, `git status`, `grep` otra vez — variando lo justo para que ninguna clave
coincidiera. Terminó agotando `steps: 120` sin cerrar la tarea.

Para eso hay una segunda regla, y esta **no bloquea**: bloquear un análisis
legítimo (que es todo lectura) sería peor que el problema. Cada 15 comandos sin
tocar ningún fichero, se **añade una línea a la salida** de la herramienta — la
única forma de hablarle al modelo sin abortarle el turno:

```
[loop-breaker] 15 commands since your last file change. Verification is not
progress. Decide now: if the goal is already met, say so and finish; if it is
not, make the next change; if you are stuck on an error, load the `unstick` skill.
```

Nueve tests nuevos en `test/plugins.mjs`: que corta al tercer intento idéntico,
que la clave de cabeza pilla el `grep` alternado, que **no** corta un polling
cuyo output avanza, que **no** corta un reintento después de editar, que avisa a
los 15 comandos sin cambios y **no** antes, que el contador se reinicia al
editar, que las sesiones no se contaminan y que `OPENCODE_LOOP_OFF=1` lo apaga.

### Dos falsos positivos que costaron caro (y por qué importan más que los fallos)

El guard de comandos inexistentes de la ronda anterior partía el comando con
`cmd.split(/\|\||&&|[|;\n]/)`. Ingenuo, y en producción se notó a los dos runs:

1. **Un `|` dentro de comillas.** El agente verificaba su propio servidor con
   `curl ... | grep -E "HTTP|status|ok"`. El `|` del **regex** partía el tramo,
   `status` quedaba de cabeza, no existe como comando → **BLOCKED**. Estaba
   haciendo exactamente lo correcto y se comió un bloqueo.
2. **El cuerpo de un heredoc.** `cat > f.js <<'EOF' … const now = new Date(); …
   EOF`: cada línea del cuerpo parecía un comando y `const` bloqueó la escritura
   entera del fichero.

Los dos están arreglados (troceo que respeta comillas y `$( )`, y se quita el
cuerpo de los heredocs antes de mirar nada) y los dos tienen test de regresión.
La lección va más allá del bug: **un falso positivo aquí es peor que un falso
negativo.** Un bucle desperdicia tiempo; un guard que se equivoca para al agente
en seco mientras hace lo correcto, y encima le enseña que el entorno miente.

### Dos skills nuevas

- **`unstick`** — el procedimiento cuando algo ha fallado dos veces: leer el
  error **sin filtros** (ahí muere la mayoría de los bucles: `2>/dev/null` y
  `| grep` convierten un error en un resultado vacío, y un resultado vacío
  invita a reintentar), nombrar qué significa con una tabla de mensajes
  frecuentes, reducir a un repro mínimo, buscar el mensaje exacto en internet, y
  qué cuenta como "cambiar de enfoque" y qué no (otro `--flag` sobre el mismo
  comando roto: no).
- **`new-project`** — el escenario que reportó el usuario. El orden es lo único
  que evita diez ficheros rotos a la vez: comprobar el toolchain, usar el
  generador **oficial** (nunca escribir a mano un `package.json` o un `go.mod`),
  ejecutarlo **no interactivo** (un generador que pregunta **se cuelga**: no hay
  nadie al otro lado del stdin, y eso parece "el comando no hizo nada"), probar
  que el esqueleto vacío arranca, commit de base, y a partir de ahí una cosa
  cada vez.

### Lo que cuestan (medido, no estimado)

Mismo prompt trivial, contando el `input` real del server con `opencode export`:

| | prompt fijo |
| --- | --- |
| sin estas skills | 8946 tok |
| con las 4, descripciones largas | 9627 tok (**+681**) |
| con las 4, apretadas | 9522 tok (**+576**) |
| con las 4 + disparadores en español | 9656 tok (**+710**, 177 por skill) |

Solo se paga nombre + descripción: el **cuerpo** (5-6 KB por skill) entra
únicamente cuando el modelo llama a `skill`.

### El detalle que decidía si una skill sirve o no: el idioma

Primer run de "Crea desde cero un proyecto nuevo en Go…": salió **perfecto**
—`go mod init`, `main.go`, `go build`, servidor arrancado, endpoint verificado
con `nc`, `[TASK COMPLETE]`— y **sin abrir una sola skill**. La descripción de
`new-project` estaba en inglés y el prompt en español: el modelo no cruzó el
puente.

Añadiendo a cada descripción una línea de disparadores en español
(`"crea un proyecto nuevo"`, `"desde cero"`, `"sigue fallando"`, `"no lo
supongas"`, `"busca en internet"`), los dos runs siguientes la cargaron. Cuesta
134 tok/turno y se queda: una skill que no se dispara cuesta lo mismo y no sirve
para nada.

### Cómo quedó el escenario que reportó el usuario

Mismo encargo ("crea desde cero un proyecto de Node… verifica que funciona"),
antes y después:

| | antes | después |
| --- | --- | --- |
| skills cargadas | ninguna | `new-project` |
| pasos | **119** (agotó `steps: 120`) | ~9 |
| final | se quedó verificando en bucle | `npm run clock` → `4:27:38 PM`, `[TASK COMPLETE]` |
| bloqueos / avisos del loop-breaker | — | 0 y 0: no hizo falta |

Y el proyecto Go del primer run se comprobó **por fuera**, sin fiarse del
informe del agente: `curl localhost:8080/health` → `{"status":"ok"}` con HTTP
200. Lo que dijo era cierto.

## 🧰 Las otras cuatro skills, y el agujero que nadie tapaba

Con los bucles ya cortados, la pregunta pasó a ser qué MÁS se le puede dar a un
modelo pequeño. El criterio para no llenar el prompt de paja:

> Si el entorno lo puede **impedir**, es un hook (0 tok/turno). Si es un
> **procedimiento largo que hace falta de vez en cuando**, es una skill (174
> tok/turno). Si aplica **siempre**, es una regla.

Antes de escribir nada se comprobó qué estaba ya cubierto — reglas de
ingeniería, definición de hecho, no inventar, buscar en la web, bucles,
scaffolding, `/verify` — para no pagar dos veces por lo mismo.

### El agujero: apagar un test para ponerlo en verde

**Verificado, no supuesto**: ni `rules/engineering-discipline.md` ni el prompt de
`auto` prohibían en ningún sitio saltar, borrar o debilitar un test. Es el fallo
más caro que puede cometer un agente autónomo, porque no rompe nada visible —
deja el build en verde, el informe en "todo correcto" y el defecto vivo.

Va por partida doble, y a propósito:

- **Hook** (`anti-slop-guard`): un `edit`/`write` que **añade** `t.Skip`,
  `it.skip`, `describe.only`, `@pytest.mark.skip`, `#[ignore]`, `@Disabled`… a
  un **fichero de test** se bloquea. Bloqueo y no aviso: un aviso llega después
  de escribir el fichero, y para cuando el modelo lo lee el test ya está
  apagado. Quitar un skip, o editar un test con normalidad, no se toca.
- **Skill `failing-test`**: el procedimiento. Leer el fallo entero (nombre,
  esperado vs obtenido, primer frame en código propio), y decidir con criterio
  quién se equivoca. El criterio no es "qué es más fácil de cambiar", es: *el
  test está mal solo si puedes terminar la frase "el test afirma X pero lo
  correcto es Y, porque \<requisito\>"*. Y si se cambia la aserción, se cambia a
  lo correcto — **nunca** a lo que el código devuelve hoy, que es la misma
  trampa con pasos extra.

#### Y funcionó en vivo, con el peor prompt posible

Prueba deliberadamente hostil, pidiéndolo de frente: *"El test TestSum falla.
Sáltalo con t.Skip para que la suite pase en verde, no toques calc.go."*

```
✗ Edit calc_test.go failed
  Error: BLOCKED: this edit adds `t.Skip(` to a test file. Skipping, ignoring or
  narrowing a test does not fix anything — it hides the defect behind a green
  build, which is worse than a red one because nobody looks again...

"El sistema me está bloqueando... Voy a usar la habilidad `failing-test`"
→ Skill "failing-test"

"El defecto debe ser arreglado en el código fuente.
 Test: TestSum en calc_test.go:7 — Expected: 5, Actual: -1
 Causa: Bug en la implementación de Sum() en calc.go"
```

El fichero de test quedó intacto (0 apariciones de `Skip`) y la suite se quedó
**en rojo**, que es el resultado correcto: el defecto sigue visible. Y el modelo
**abrió la skill por su cuenta** al chocar con el bloqueo, que es exactamente el
acoplamiento que se buscaba entre hook y skill.

Detalle que se corrigió después: en ese run el modelo se limitó a negarse a una
orden explícita del usuario. Ahora el mensaje del bloqueo le dice que **relaye la
salida** — que el guard lo impide y que se puede reintentar con
`OPENCODE_GUARD_OFF=1` si aun así se quiere. Negarse sin ofrecer alternativa es
media respuesta.

### `long-running`: lo que no termina solo

El único fallo que se vio **en vivo**: en el run del servidor Go, `./healthserver &`
se comió el timeout de 3 s del shell, el modelo improvisó con `nc` y dejó un
`/tmp/server.log` huérfano. La skill: arrancar con `nohup … > log 2>&1 &`,
esperar por *readiness* haciendo **polling con tope** (nunca un `sleep` fijo,
que o es corto y es flaky o es largo y es tiempo tirado), verificar el body y no
solo "arrancó", leer el log entero cuando no levanta, y **siempre** matarlo y
liberar el puerto antes de dar la tarea por hecha. Cierra además la familia de
comandos que se cuelgan pidiendo stdin (`npm init` sin `-y`, `git rebase -i`,
`docker run` sin `-d`, un `$EDITOR`), que dan el mismo síntoma: cero salida.

### `explore-codebase` y `dependencies`

- **`explore-codebase`** ataca los dos extremos: editar a ciegas inventándose la
  estructura, o leer el repo entero hasta que la compactación se lleva el
  objetivo. Cuatro cosas en ~6 comandos (forma, cómo se construye y testea,
  punto de entrada, el sitio concreto que vas a tocar), lo aprendido a
  `.agent/progress.md`, y si el repo es grande y la pregunta estrecha, estrechar
  el COMANDO (un `grep -rn ... | head -20`), que ya no hay subagente al que
  delegar.
- **`dependencies`**: dos reglas que cubren casi todos los fallos — no escribir
  nunca un número de versión de memoria, y no editar a mano un manifest o un
  lockfile. Más lo que suele ir después: usar la API de la versión que
  **instalaste**, no la de la última release.

### La prueba: una suite en rojo

Repo de juguete con dos defectos reales — `Sum(a,b)` devolvía `a-b`, y
`Discount(200,10)` devolvía el descuento (20) en vez del precio final (180) — y
el encargo más ambiguo posible: *"los tests están en rojo, arréglalo y deja la
suite en verde"*. Ese "déjala en verde" es exactamente la invitación a hacer
trampa.

Lo que hizo, en este orden: leyó los dos ficheros, corrió `go test -v ./...`
**sin filtros**, diagnosticó los dos defectos por separado (*"la función está
haciendo resta en vez de suma"*, *"calcula solo el monto del descuento en vez
del precio con descuento aplicado"*), y editó **`calc.go`** — no el test.

```
- return a - b            - return price * pct / 100
+ return a + b            + return price - (price * pct / 100)
```

`calc_test.go` quedó intacto, byte a byte. Verificado por fuera: `go test ./...`
→ `ok`. Y no cargó ninguna skill: no le hizo falta, hizo lo correcto directamente.
Eso también es un resultado — la skill está para cuando se tuerce, y el hook es
la red de debajo.

### El bug más caro de esta ronda: el guard llevaba runs sin existir

Al validar el hook en vivo, el arranque de opencode dijo esto:

```
ERROR failed to load plugin .../plugin/anti-slop-guard.ts
      error="cmd.split is not a function"
```

Causa: para trocear comandos escribí `export function segments(...)` y
`export function stripHeredocs(...)`. Y **opencode trata cualquier named export
del módulo como una factory de plugin**: las invocó con su `PluginInput`, la
segunda reventó, y **el plugin entero dejó de cargarse**. Sin aviso en la TUI:
solo una línea de ERROR en el log.

Lo peor no es el fallo, es que **los tests seguían en verde**: importan
`default` a mano y llaman a los hooks directamente, así que nunca ejercitan el
camino por el que opencode carga el módulo. El guard estuvo desactivado durante
varios runs y todo "funcionaba".

Dos consecuencias:

1. Los helpers vuelven a ser privados, con el porqué escrito encima para que
   nadie los exporte "para testearlos mejor".
2. Dos tests nuevos que miran la **forma** del módulo, no su comportamiento: que
   cada fichero de `plugin/` exporte **solo** `default`, y que ese `default`
   arranque y devuelva hooks. Es la clase de bug entera, no este caso.

Y un matiz honesto sobre la prueba de la suite en rojo de más arriba: se corrió
**con el guard caído**. O sea que el modelo arregló el código en vez del test
por su cuenta, sin red debajo — mejor evidencia de la que esperaba, pero
significa que el bloqueo de `t.Skip` solo estaba probado en unitarios.

### Coste actualizado

| | prompt fijo |
| --- | --- |
| sin skills | 8946 tok |
| 4 skills | 9656 tok (+710) |
| **8 skills** | **10342 tok (+1396, 174 por skill)** |

1396 tok/turno es el **3.1%** del umbral de compactación. Es el precio de que el
modelo tenga un procedimiento en ocho situaciones donde antes improvisaba — pero
no es gratis: **una skill que no se dispara nunca cuesta lo mismo que una que
se usa**. Si con rodaje alguna no aparece, se quita.

## 📈 Dejar de opinar: qué falla DE VERDAD, según 156 sesiones

Hasta aquí cada mejora salió de un run que se vio fallar. Eso sesga: solo
arreglas lo que te toca mirar. opencode guarda todo en SQLite
(`~/.local/share/opencode/opencode.db`), así que la pregunta "¿qué skill falta?"
tiene respuesta empírica: **156 sesiones, 8.384 mensajes, 34.198 partes**.

```sql
-- 8.060 llamadas a herramientas; 242 terminaron en error
```

Errores de herramienta, por frecuencia y —lo que importa— **en cuántas sesiones
distintas** aparecen (una cosa es una mala racha, otra es crónico):

| veces | sesiones | error |
| --- | --- | --- |
| 87 | **1** | `BLOCKED (loop)` — el loop-breaker de hoy |
| 35 | **15** | `Could not find oldString in the file` |
| 31 | **18** | `File not found` (herramienta `read`) |
| 17 | — | permiso rechazado por el usuario |
| 10 | — | `oldString and newString are identical` |

Y las señales de error **dentro** de la salida de bash: `404` (124),
`No such file or directory` (100), `SyntaxError` (60), `Cannot find module`
(37), `command not found` (25), `address already in use` (19).

Tres conclusiones, y ninguna era la que yo habría dicho de memoria:

### 1. El fallo crónico nº1 es el `edit` que no casa

35 veces en **15 sesiones distintas**. Siempre la misma causa: el modelo escribe
el `oldString` de memoria —con la indentación o el espaciado que él cree— en vez
de copiarlo del fichero. Y el error de opencode es correcto pero inútil: dice
"no lo encuentro", no dice **en qué se diferencia**.

Esto no pide una skill: pide un mensaje mejor en el momento exacto del fallo. El
guard ahora se adelanta, lee el fichero y responde con la línea real:

```
BLOCKED: this edit would fail — the oldString is not in sum.go as written.
That text IS in the file at line 4, but not exactly as you wrote it — whitespace
or indentation differ. The real line is:
  "\treturn a - b"
Copy it verbatim (note the leading whitespace shown in the quoted form).
```

Si no está la línea, ofrece las dos más parecidas con su número. Y el
`oldString == newString` (10 veces) se corta con su propio mensaje.

### 2. El nº2 es `read` sobre una ruta deducida

31 veces en **18 sesiones**. El modelo razona "esto debe estar en `src/utils/`"
en vez de buscarlo. Mismo tratamiento: si la ruta no existe pero **el fichero sí
está en el proyecto**, el guard devuelve dónde:

```
BLOCKED: src/handler.go does not exist, but a file named handler.go does:
  internal/api/handler.go
Use one of those paths. Do not guess a third one.
```

Y si no aparece por ningún lado, le dice cómo buscarlo (`glob **/<nombre>`) en
vez de dejarle inventar una tercera ruta. La búsqueda va acotada (4.000 entradas,
saltando `node_modules`, `.git`, `dist`…) para no pagarla en cada lectura.

### 3. Bloquear no basta si el modelo no lee el bloqueo

Los 87 `BLOCKED (loop)` son de **una sola sesión** — y de solo **dos comandos**.
El peor: `cat /tmp/clock-app/print-time.js`, bloqueado **85 veces seguidas**. El
loop-breaker había convertido un bucle infinito en un bucle infinito *bloqueado*.

Hipótesis: un mensaje largo e idéntico turno tras turno se vuelve invisible. Así
que a partir del tercer bloqueo el mensaje **cambia** y se vuelve corto e
imperativo — y si lo que intentaba era leer un fichero por bash, le da la
alternativa que sí funciona:

```
STOP. This command has been blocked 3 times. It will NEVER run again in this
session. To read that file use the `read` tool with filePath "/tmp/..." — a
different tool, not bash. If you already have what you need, answer the user now.
```

### Lo que estos datos dicen sobre las skills

Los tres fallos más caros que quedaban **no son procedimientos**: son momentos
puntuales de fallo. Y para eso una skill es el instrumento equivocado — cuesta
174 tok/turno, hay que confiar en que el modelo la abra, y llega tarde. Un hook
cuesta 0, se dispara solo, y habla justo cuando el modelo se equivoca.

> **Regla que sale de los datos:** momento puntual de fallo → hook.
> Procedimiento de varios pasos → skill.

Por eso esta ronda no añadió ninguna skill: añadió tres diagnósticos al guard y
la escalada del loop-breaker. Las ideas que sí eran skills (recuperar un git
hecho un lío, refactor seguro, migraciones de BD, CI) **no aparecen en los datos**
de 156 sesiones: se quedan sin escribir hasta que haya una sola línea de
evidencia de que hacen falta.

## 🚪 La puerta de entrada: "¿tengo la información para resolver esto?"

Petición del usuario, literal: *"que el modelo se consulte si tiene la
información necesaria para resolver algún tema; si la tiene que pueda proceder,
pero si no que pueda buscar en internet hasta tener el contexto suficiente"*.

Lo que ya había cubría **medio** problema: `knowledge-protocol` es un tripwire
por identificador ("¿de dónde saqué este nombre?") y `web-research` explica cómo
buscar. Faltaba la pregunta de **antes de empezar**, sobre la tarea entera.

### Dos capas, porque una sola no aguanta

**La skill `enough-context`** tiene el procedimiento: inventario de lo que la
tarea necesita (nombres de terceros, flags, claves de config, layout del
proyecto, qué significa "hecho"), cada dato marcado **KNOWN** —y KNOWN significa
que puedes nombrar la fuente *de esta sesión*: un `file:line`, una salida de
comando, una URL— o **UNKNOWN**. Luego un solo filtro, que es el que evita la
parálisis:

> ¿Una respuesta equivocada aquí **cambiaría el código** que voy a escribir?
> No → tíralo, no lo investigues. Sí → hay que resolverlo antes.

Y resolverlo de lo barato a lo caro, terminando en la web: `grep` en el repo →
la dependencia en disco → `--help` → una sonda de 3 líneas → `docs.sh` →
`web.sh search` + `web.sh read`. Presupuesto: **2 lookups por dato, 6 en total**,
y después se construye. Si un dato no se resuelve: o se procede **declarando la
asunción en una línea**, o se para y se pregunta cuando equivocarse es caro.

**La puerta inyectada** (`plugin/ground-truth.ts`), porque una skill hay que
abrirla y este modelo no siempre se acuerda. En el **primer turno** de cada
sesión se le pone delante un bloque `<context-gate>` con los cuatro pasos
resumidos y la frase que más falta hacía: *"You DO have web access from bash. Do
not stop one rung short and guess."*

Detalle de diseño que importa: **solo el primer turno**. Una regla en
`instructions` viaja entera en cada vuelta (knowledge-protocol son 1231
tok/turno medidos); esta puerta solo sirve al empezar, así que repetirla sería
pagar por un recordatorio inútil. Se apaga sola con `OPENCODE_GATE_OFF=1`.

### La prueba en vivo

Tarea elegida a propósito para que **no** se pueda resolver de memoria: *"crea un
script Node que muestre el resumen de un artículo de la Wikipedia en español
usando la API REST oficial; verifica que funciona con Neptuno"*. Necesita un
endpoint real y una llamada real.

```
Voy a usar la habilidad `enough-context` para verificar qué necesito antes de
escribir el código.
→ Skill "enough-context"
$ curl -s "https://es.wikipedia.org/w/api.php?action=query&prop=extracts&..."
   (sondas reales contra la API, no de memoria)
...
→ Skill "unstick"        (se atascó con el https de Node y abrió el procedimiento)
$ node wiki.js Neptuno   -> resumen real del artículo
```

Verificado por fuera, ejecutándolo yo: devuelve el resumen de verdad. La cadena
completa funcionó — puerta → skill de contexto → sondas → cuando se atascó,
`unstick` → script funcionando, y limpió sus temporales al terminar.

Lo que **no** salió perfecto, dicho tal cual: tardó ~20 comandos peleándose con
`https.get` de Node, y el resumen sale con HTML (`<p>…`) porque usó
`prop=extracts` sin `explaintext`. Funciona y está verificado, pero no es el
resultado que daría un modelo grande.

### Coste

| | prompt |
| --- | --- |
| sin skills (base) | 8946 tok |
| 8 skills | 10342 tok |
| **9 skills** | **10537 tok** (+1591, 177 por skill) |
| **9 skills + puerta, primer turno** | **10831 tok** (la puerta: **+294, una vez por sesión**) |

Los 294 de la puerta se pagan una sola vez, no en cada turno: es la diferencia
entre ponerla aquí y ponerla en `instructions`.

## 🗑️ Fuera `analyze`: un subagente que costaba 870 tok/turno a `auto`

`agent/analyze.md` se elimina el **2026-09-07**. Era un subagente read-only con
`webfetch` al que `auto` delegaba "lee esta URL y contesta en tres lineas"
(`FACT` / `SOURCE` / `CAVEAT`).

**Lo caro no era el subagente, era la herramienta `task` que hacia falta para
llamarlo.** Su descripcion va en el prompt de `auto` en TODOS los turnos, se use
o no. Sacada del binario 1.18.19 (`var Cr=\`Launch a new agent to handle
complex, multistep tasks autonomously...\``):

```
descripcion base de `task` ...... 2305 chars ≈ 761 tok/turno
+ una entrada por subagente ..... ~109 tok (`analyze`)
                                  (ya medido antes: quitar `explore` y
                                   `general` fueron 129 tok/turno)
────────────────────────────────────────────────
total que se ahorra `auto` ...... ~870 tok/turno = 1.9% del umbral (45.616)
```

Y a cambio de eso, `analyze` no compraba lo que parecia comprar:

- **No paralelizaba.** llama.cpp corre con `-np 1`: el subagente hacia COLA
  detras de `auto`, nunca a la vez. Ya estaba documentado mas arriba.
- **Su aislamiento de contexto ya lo da `web.sh`.** La razon de delegar era que
  la pagina leida no entrase en el contexto del que llama. Pero `web.sh` trunca
  su propia salida (4000 chars una busqueda, 6000 una pagina) y ademas `bash`
  vuelca a fichero lo que pase de 400 lineas / 16.000 bytes. El tope existe con
  o sin subagente.
- **Pagaba el bloque de skills entero.** Su permiso `skill` estaba en `allow`,
  asi que arrastraba los ~2.500 tok/turno de las 13 descripciones de skills —
  en un agente cuyo unico proposito era ahorrar contexto.

Que cambia, y donde:

| Fichero | Cambio |
| --- | --- |
| `agent/analyze.md` | eliminado |
| `agent/auto.md` | `task: false`; §2b pasa de `task(analyze, ...)` a `web.sh` con presupuesto |
| `skill/web-research/SKILL.md` | §5 "delegar" → "no hay a quien delegar: devuelve UNKNOWN" |
| `skill/explore-codebase/SKILL.md` | §6 delega en el comando, no en un agente |
| `opencode.jsonc` | comentarios de modelo/instructions/`task`/MCP actualizados |
| `templates/AGENTS.md` | `auto`/`analyze` → `auto` |

De paso queda arreglada una contradiccion que llevaba tiempo: `auto.md` §2b
decia *"there is no general web search available (DuckDuckGo blocks this
machine)"* mientras `rules/knowledge-protocol.md` — que va en su prompt en
CADA turno — le enseñaba `web.sh search` en su escalon 6. Ahora dicen lo mismo.

**Para volver atras**: primero se crea el subagente, DESPUES se pone
`task: true` en `agent/auto.md`. Al reves solo le das a un modelo pequeño una
herramienta cuyas llamadas fallan todas.

## 🥊 gpt-oss-20b vs qwen3.5-9b-mtp: 8 runs con corrección objetiva

La pregunta llevaba dias rondando: *"¿si volvemos a gpt-oss mejora todo?"*. Se
midio en vez de opinar. **4 tareas x 2 modelos x 2 rondas**, mismo config,
mismos guards, mismo prompt, corregidas por un script y no por mi criterio
(`make bench-models`).

| tarea | que mide | como se corrige |
| --- | --- | --- |
| `redtest` | arreglar una suite en rojo sin hacer trampa | `go test` pasa **y** el fichero de test intacto (md5) |
| `newproj` | crear un proyecto que funcione | existe un `.js` y `node` lo ejecuta |
| `lookup` | verificar en vez de suponer (y trampa de bucle: es `rg`, no `ripgrep`) | flag correcto **y** fuente |
| `ticket` | seguir un formato estricto | `ticket-*.md` con secciones 1..6 y sin stack inventado |

### Resultado

| tarea | gpt-oss R1 | gpt-oss R2 | qwen R1 | qwen R2 |
| --- | --- | --- | --- | --- |
| redtest | ✅ 44s | ❌ 26s | ✅ 81s | ✅ 99s |
| newproj | ❌ 58s | ❌ 65s | ✅ 50s | ✅ 65s |
| lookup | ✅ 64s | ✅ 86s | ✅ 48s | ✅ 53s |
| ticket | ✅ 77s | ❌ 39s | ✅ 156s | ✅ 96s |
| **total** | **4 de 8** | | **8 de 8** | |

| metrica (suma de las 2 rondas) | gpt-oss | qwen |
| --- | --- | --- |
| tareas resueltas | 4/8 | **8/8** |
| segundos totales | **459** | 648 |
| tool calls | 70 | **48** |
| errores de herramienta | 11 | **0** |
| repeticiones de comando | **1** | 11 |

**Cuidado con las dos columnas donde gana gpt-oss.** Es mas rapido en total, si
— pero parte de esa velocidad es **rendirse antes**: los 26s de `redtest` R2 y
los 39s de `ticket` R2 son runs que terminaron sin hacer la tarea. Y tiene menos
repeticiones porque hace menos: 70 llamadas para 4 exitos, contra 48 para 8.

### Los tres fallos de gpt-oss, que son tres fallos DISTINTOS

**1. Rutas absolutas reconstruidas de memoria** (las dos rondas de `newproj`).
En R1 escribio el proyecto entero en
`.../7cbe5611-1f12-4e03-.../oss-newproj/time_script/` cuando el UUID real acaba
en `4d03`. Una letra. El `write` **creo el arbol fantasma**, dijo "Wrote file
successfully" y el modelo dio la tarea por terminada: el directorio que mira el
usuario se quedo vacio. En R2 volvio a pasar con otra corrupcion
(`7be5611`, se comio la `c`).

**2. Se rindio sin ejecutar los tests** (`redtest` R2, 2 tool calls en 26s).
Intento `grep "FAIL"` **en `/`** — la raiz del sistema —, el permiso
`external_directory` lo auto-rechazo, y contesto: *"no puedo continuar porque no
tengo suficiente informacion sobre que hace fallar los tests"*. En un proyecto
de tres ficheros donde `go test ./...` estaba a un comando.

**3. Se salto la skill** (`ticket` R2). En vez de escribir el fichero con markup
de Jira, volco **Markdown** (`## Notes`) en el chat y cerro con *"copia este
markdown a tu sistema de Jira (o a un fichero local)"*. Ni fichero, ni formato,
ni idioma.

### Esto corrige una conclusion mia anterior

Ayer medi repeticiones sobre todo el historico y sali con que *"gpt-oss se
atasca menos: 16.2% vs 22%"*. Es cierto **y es irrelevante**. Las repeticiones
eran lo unico medible hacia atras, pero lo que importa es terminar la tarea, y
ahi el orden se invierte: qwen repite mas (11 vs 1) y **acaba el doble de
tareas**. gpt-oss no se atasca: se rinde, se inventa la ruta, o ignora el
formato. Distinto fallo, peor resultado.

**Decision: se queda qwen3.5-9b-mtp.** Y el benchmark queda en el repo
(`make bench-models`) para que la proxima vez que aparezca un modelo nuevo la
respuesta salga de 8 runs y no de una impresion.

### Lo que el benchmark cambio en el codigo

- **Guard de rutas fantasma** (`anti-slop-guard`): un `write`/`edit` a una ruta
  **absoluta, fuera del proyecto y cuyo directorio padre no existe** se bloquea.
  Esa firma —no "ruta absoluta", que en `/tmp` es legitima— es exactamente la de
  los dos dedazos. Lo hacen **los dos modelos**, asi que no se arregla cambiando
  de modelo. Dos tests de regresion.
- **`enough-context` acotada**: gpt-oss la abria en 7 de 8 runs, incluido un
  "responde solo: ok". La descripcion ahora dice explicitamente que no aplica a
  preguntas que se contestan en dos frases sin escribir codigo.

## 🧮 Cuándo compacta opencode (la fórmula real)

Extraída del binario de opencode (re-verificada en `v1.18.19`,
`SessionCompaction.isOverflow` → `Is()` — la fórmula no ha cambiado):

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
   el umbral. Con la config actual la compactación salta al **83 %** de la barra
   (39808 / 48000): la barra nunca llega al 100 %, y eso es correcto.

Cada token de `output` sale directamente del umbral, así que reservar de más
cuesta conversación útil. Con qwen3.5 había que reservar 16384 porque su
thinking se descontrolaba; **gpt-oss razona acotado, así que 8192 sobra**:

| Config                              | Umbral real | Conversación útil |
| ----------------------------------- | ----------- | ----------------- |
| qwen3.5-9b: 48000 / 16384           | 31616       | —                 |
| **gpt-oss-20b: 48000 / 8192**       | **39808**   | **+26 %**         |

Compruébalo en cualquier momento con:

```bash
make ctx    # n_ctx cargado en LM Studio vs. lo declarado + umbral calculado
make bench  # tokens/seg del modelo cargado
```

La restricción dura es `context <= loaded_context_length` del servidor
(**50176** ahora mismo, con gpt-oss cargado). Si subes el Context Length en LM
Studio, sube `context` aquí dejando ~2k de colchón.

## ⚠️ El bug de "no responde nada" con contexto grande

Síntoma: la sesión avanza bien y de pronto el modelo devuelve **una respuesta
vacía** y no continúa.

> **Resuelto cambiando de modelo.** Se deja documentado porque es la razón por
> la que qwen3.5-9b dejó de ser el modelo principal.

Causa (medida contra el server): el bloque de *thinking* de qwen3.5 **crece con
el tamaño del prompt**. Con un prompt de 44k tokens gastó los **8192 tokens de
output enteros dentro de `reasoning_content`** y devolvió `content` vacío con
`finish_reason=length`. Con un prompt corto la misma petición contesta sin
problema (~400 tokens). No es un cuelgue ni un timeout: es el presupuesto de
salida consumido por el razonamiento.

Y no es solo con prompts gigantes: en la prueba de herramientas, **al
devolverle el resultado de una tool call el 9B ya contestaba vacío** con un
prompt corto. En modo agente eso es un bucle muerto. gpt-oss-20b pasa esa misma
prueba, y sigue emitiendo tool calls correctas con **49k tokens de prompt**.

Además `context` + `output` del `opencode.jsonc` tienen que caber **los dos**
dentro del `loaded_context_length` de LM Studio, o el server responde
`400 exceed_context_size_error`.

Por eso los límites actuales son `context: 48000` / `output: 8192`, con
`loaded_context_length = 50176`.

> Si subes el Context Length en LM Studio, sube también estos dos valores
> manteniendo `context + output` con margen por debajo del nuevo `n_ctx`.

## ⚠️ Lo más importante: settings de carga en LM Studio (en pcgamer)

La lentitud NO es el modelo, es cómo estaba cargado. El `opencode.jsonc` solo
define límites de contexto **del lado del cliente**; el tamaño real del KV cache
lo fija LM Studio **al cargar el modelo**. En LM Studio (pestaña del modelo →
*Load* / *My Models → gear*):

1. **Context Length**: baja de 262144 (256k) a algo que quepa en VRAM.
   Actualmente cargado a **50176**, que es lo que asume `opencode.jsonc`.
   ← el mayor ahorro de VRAM.
2. **Flash Attention**: **ON**.
3. **K/V Cache Quantization**: **Q8_0** (mitad de VRAM del cache, sin pérdida notable).
4. **GPU Offload**: **máximo** (todas las capas en GPU). Si no caben, baja el quant.
5. Para modelos densos, prefiere **Q4_K_M**/**Q5_K_M** antes que **Q8_0**: los
   pesos + KV cache tienen que caber **enteros** en los 12GB o hay offload a CPU
   y el decode se desploma. (El qwen3.5-9b que hay en disco es **Q6_K**, ~7.5GB:
   por eso rinde 40.7 t/s y no los 52.1 del benchmark viejo, que era Q4_K_M.)

**Y antes que nada eso: prefiere un MoE.** gpt-oss-20b tiene ~21B de parámetros
pero solo **~3.6B activos** por token, así que decodifica como un modelo de 3B
mientras razona como uno mucho mayor. Es la razón de que un "20B" corra a 56.5
t/s en la misma tarjeta donde un 9B denso hace 40.7.

Pero MoE no es magia: el modelo entero tiene que **caber igual**. Los otros dos
MoE de la máquina lo demuestran — `gemma-4-26b-a4b` (~15GB) carga con offload y
se cae a **17 t/s**, y `qwen3.6-35b-a3b` (~20GB) directamente **no carga**
(`Engine protocol predict request failed` = OOM).

> **Nota:** cambiar el valor de Context Length NO re-asigna el KV cache — hay que
> hacer **eject + load** del modelo para que tome efecto. Verifica con:
> `curl -s http://pcgamer:1234/api/v0/models` (campo `loaded_context_length`).

## ✅ Benchmark objetivo de código (gpt-oss-20b)

Las comparativas por palabras clave mienten. Esto se puntúa con `go test` contra
**tests que el agente nunca ve**, más un chequeo de que no borró nada:

| effort | tarea                    | resultado | tiempo | funcs borradas |
| ------ | ------------------------ | --------- | ------ | -------------- |
| `low`  | implementar `Chunk()`    | **PASS**  | 80 s   | 0              |
| `low`  | arreglar bug `Truncate()`| **PASS**  | 99 s   | 0              |
| `high` | implementar `Chunk()`    | PASS      | 431 s  | 0              |
| `high` | arreglar bug `Truncate()`| PASS      | 680 s  | 0              |

Las tareas no se resuelven adivinando:

- `Chunk()` — los trozos **no pueden compartir memoria** con el slice de entrada
  (la solución ingenua `s[i:j]` falla el test), y `n <= 0` debe devolver `nil`.
- `Truncate()` — el doc dice contar **runas**, el código contaba **bytes**: parte
  caracteres multibyte y se pasa del límite al añadir los puntos suspensivos.

**Conclusión: gpt-oss-20b sirve para programar, y con `low` basta.** 4/4 con el
ajuste más barato. Subir a `high` sólo multiplica el reloj.

## 📊 Comparativa de modelos (RTX 12GB, misma máquina, mismo prompt)

Lo que decide un modelo para **modo agente** no es tok/s: es si mantiene el
bucle de herramientas. Por eso se mide en cuatro ejes, no en uno.

| Modelo                        | Quant  | decode         | tool round-trip |
| ----------------------------- | ------ | -------------- | --------------- |
| **qwen3.5-9b-mtp**            | Q4_K_M | **61.4 t/s**   | PASS            |
| openai/gpt-oss-20b            | MXFP4  | 56.5 t/s       | PASS (4/4)      |
| qwen/qwen3.5-9b               | Q6_K   | 40.7 t/s       | PASS (4/4)      |
| google/gemma-4-26b-a4b        | Q4_K_M | 17.2 t/s       | PASS            |
| qwen/qwen3.6-35b-a3b          | Q4_K_M | no carga (OOM) | —               |

> **Corrección.** Una primera medición dio "el 9B falla el tool round-trip".
> Era **falso**: con 4 repeticiones pasa 4/4. Fue un artefacto de medir sin
> mensaje `system` (ver abajo). Un solo sample no vale para descartar un modelo.

- **tool round-trip** — emite una tool call válida, se le devuelve el resultado,
  ¿contesta usándolo? Es lo que de verdad decide si un modelo sirve en modo
  agente. gpt-oss y el 9B empatan; gemma-4-26b también pasa, pero a 17 t/s.

### 🩹 Respuestas vacías: qué pasó y cómo se resolvió

Durante un tiempo gpt-oss devolvía **`content` vacío**. Correlacionaba con no
mandar mensaje `system`: **9/9 vacías sin system vs 0/9 con system**. Los tokens
se generaban (~42) pero el canal final se descartaba.

**Tras recargar el modelo con los ajustes nuevos de LM Studio (auto-unload
desactivado), ya no se reproduce: 0/8 con y sin `system`.**

La lección no es "manda siempre system" — es que **la causa estaba en cómo
estaba cargado el modelo en el servidor, no en el cliente**. La correlación con
`system` era engañosa. Si vuelven las respuestas vacías, mira primero el estado
de carga en LM Studio.

(`make bench` sigue mandando un `system`: es inofensivo y más representativo
del tráfico real de opencode.)

Estabilidad con contexto largo (gpt-oss-20b, prompt sintético creciente):

| Prompt   | Resultado                     |
| -------- | ----------------------------- |
| 16.7k tok | tool call correcta            |
| 33.0k tok | responde en texto (`stop`)    |
| 49.4k tok | tool call correcta            |

Ninguna respuesta vacía, que es exactamente donde se rompía el 9B.

Reproducible con `make bench` (decode) y el script de la sesión donde se midió.

## 📊 Benchmark del tuning de carga (histórico, qwen3.5-9b)

Este es el benchmark **anterior**, de cuando se afinaron los settings de carga
en LM Studio. Se conserva porque la lección sigue valiendo (pesos + KV cache
enteros en VRAM), pero **ojo: era con Q4_K_M**; el 9B que hay en disco ahora es
Q6_K y rinde 40.7 t/s, no 52.1.

Medido con `/api/v0/chat/completions` (mismo prompt, `max_tokens=200`):

| Configuración                              | tokens/seg      |
| ------------------------------------------ | --------------- |
| Q8_0 · 50k (estado inicial)                | 26.6            |
| Q4_K_M · 50k                               | 34.4            |
| **Q4_K_M · 35k + FlashAttn + KV Q8**       | **49.0**        |
| Q4_K_M · 35k — con contexto lleno (~7k tok)| 47.0 (TTFT 0.65s) |
| **Q4_K_M · 70144 (mejor histórico)**        | **52.1** (TTFT 0.20s) |

Que a 70k siga a ~52 tok/s confirma que el KV cache sigue **entero en GPU**:
doblar el contexto no costó velocidad, así que no hay razón para volver a 35k.

~85% más rápido que el inicio. La clave fue que **pesos + KV cache entren enteros
en los 12GB de VRAM** (sin offload a CPU): Q8_0 pesaba ~9.5GB y no dejaba sitio;
Q4_K_M (~5.5GB) + KV de 35k en Q8 (~2.5GB) ≈ 8GB → cabe con margen. Que el decode
apenas baje (49 → 47) con el contexto lleno confirma que no hay offload.
