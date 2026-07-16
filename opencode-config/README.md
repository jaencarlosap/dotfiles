# opencode-config

Configuración de [opencode](https://opencode.ai) versionada con git, apuntando a
un servidor local de modelos (**LM Studio** en `pcgamer`, vía Tailscale, 12GB VRAM).

El repo es la **fuente de verdad**. `make install` reemplaza los archivos en
`~/.config/opencode` por *symlinks* hacia este repo.

## Uso

```bash
make install     # crea los symlinks (respalda lo previo)
make status      # ver estado de los symlinks
make test-conn   # ping a LM Studio en pcgamer
make models      # lista modelos disponibles
make uninstall   # quita los symlinks
make restore     # restaura el ultimo respaldo
```

## Qué se versiona

| Archivo             | Rol                                                        |
| ------------------- | ---------------------------------------------------------- |
| `opencode.jsonc`    | Config principal: provider LM Studio, modelos, permisos    |
| `agent/auto.md`     | Agente primario de coding (Qwen3.5 9B)                     |
| `agent/analyze.md`  | Agente de análisis/arquitectura (DeepSeek-R1 14B, read-only) |

## Modelos y para qué sirve cada uno (12GB VRAM)

| Modelo                         | Uso recomendado           | Nota de carga en LM Studio            |
| ------------------------------ | ------------------------- | ------------------------------------- |
| **qwen/qwen3.5-9b**            | Coding principal (rápido) | Q4_K_M/Q5_K_M · ctx 24-32k · FlashAttn |
| **openai/gpt-oss-20b**         | Agéntico fuerte           | MXFP4 ~11GB · ctx ≤12k (justo)        |
| **deepseek-r1-distill-qwen-14b** | Análisis/razonamiento   | Q4_K_M ~8.5GB · ctx ≤16k              |
| **phi-4-mini-instruct**        | small_model / tareas rápidas | Q4 ~2.5GB · muy rápido             |
| **zai-org/glm-4.6v-flash**     | Visión (screenshots/UI)   | Q6 ~8GB                               |
| **mistral-7b-instruct**        | General rápido            | Q4 ~4.5GB                             |
| **codestral-22b** (opcional)   | Código (Q3, calidad baja) | Q3_K_M ~10.5GB · justo                |

## ⚠️ Lo más importante: settings de carga en LM Studio (en pcgamer)

La lentitud NO es el modelo, es cómo estaba cargado. El `opencode.jsonc` solo
define límites de contexto **del lado del cliente**; el tamaño real del KV cache
lo fija LM Studio **al cargar el modelo**. En LM Studio (pestaña del modelo →
*Load* / *My Models → gear*):

1. **Context Length**: baja de 262144 (256k) a **24000–32000**. ← el mayor ahorro de VRAM.
2. **Flash Attention**: **ON**.
3. **K/V Cache Quantization**: **Q8_0** (mitad de VRAM del cache, sin pérdida notable).
4. **GPU Offload**: **máximo** (todas las capas en GPU). Si no caben, baja el quant.
5. Prefiere GGUF **Q4_K_M** o **Q5_K_M** en vez de **Q8_0** para el 9B
   (Q8 pesa ~9.5GB y no deja espacio para el contexto en 12GB).

Con esto el 9B corre 100% en GPU y responde varias veces más rápido.
