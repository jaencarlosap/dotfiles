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

~85% más rápido que el inicio. La clave fue que **pesos + KV cache entren enteros
en los 12GB de VRAM** (sin offload a CPU): Q8_0 pesaba ~9.5GB y no dejaba sitio;
Q4_K_M (~5.5GB) + KV de 35k en Q8 (~2.5GB) ≈ 8GB → cabe con margen. Que el decode
apenas baje (49 → 47) con el contexto lleno confirma que no hay offload.
