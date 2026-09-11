# bench — comparar modelos con datos, no con opiniones

Cuatro tareas con correccion OBJETIVA (no "parece buena respuesta"):

| tarea | que mide | como se corrige |
| --- | --- | --- |
| `redtest` | arreglar una suite en rojo sin hacer trampa | `go test` pasa **y** el fichero de test esta intacto (md5) |
| `newproj` | crear un proyecto de cero que funcione | existe un `.js` y `node` lo ejecuta sin error |
| `lookup` | verificar un dato en vez de suponerlo | la respuesta trae el flag correcto **y** una fuente |
| `ticket` | seguir un formato estricto | existe `ticket-*.md` con secciones 1..6 y sin stack inventado |

`lookup` es ademas una trampa de bucle: el binario se llama `rg`, no `ripgrep`.

## Uso

```bash
make bench-models                                  # qwen-35b y qwen-9b, las 4 tareas
make bench-models MODEL=lmstudio/gpt-oss-20b TAG=oss   # uno solo
```

Los ids salen de `make models` (son los de llama-swap, no rutas de
HuggingFace). Un id que no existe ya no cae de vuelta al modelo cargado: da
`404 no router for requested model` y el run se pierde entero.

⚠️ **Un bench por vez.** llama.cpp corre con `-np 1`: dos peticiones a la vez
se serializan, y comparar dos modelos obliga ademas a descargar uno y cargar el
otro. Si lanzas algo en paralelo, los tiempos que midas no son del modelo.

Cada run deja `run.txt` y `.seconds` en su directorio. Despues:

```bash
bash bench/score.sh <tarea> <dir>     # PASS/FAIL objetivo
python3 bench/metrics.py <dir>        # tool calls, errores, repeticiones, skills
```

`metrics.py` saca las metricas de `opencode.db` buscando la ULTIMA sesion de ese
directorio, asi que corrige y mide sobre el run real, no sobre lo que diga el
modelo de si mismo.

## Por que estas metricas

- **repeticiones** (ejecuciones identicas del mismo comando) es la unica señal de
  bucle que se puede calcular hacia atras en todo el historico.
- **skills** dice si el andamiaje se dispara o solo cuesta tokens.
- **bloqueos** separa "el modelo se equivoco" de "el entorno lo paro a tiempo".
