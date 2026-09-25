# ─────────────────────────────────────────────────────────────────────────
# opencode-config — configuracion versionada de opencode
#
# El repo es la fuente de verdad. `make install` reemplaza los archivos de
# ~/.config/opencode por SYMLINKS que apuntan aqui, para poder versionar con git.
# ─────────────────────────────────────────────────────────────────────────

SHELL        := /bin/bash
REPO_DIR     := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
TARGET_DIR   := $(HOME)/.config/opencode
BACKUP_DIR   := $(REPO_DIR)/.backups
STAMP        := $(shell date +%Y%m%d-%H%M%S)

# Archivos/carpetas que gestionamos (relativos a TARGET_DIR)
LINKS        := opencode.jsonc agent rules command plugin bin templates skill memory mcporter

# Endpoint del PC con los modelos: llama-swap delante de llama.cpp, via
# Tailscale. NO es LM Studio (lo fue). Se nota en dos sitios:
#   - no existe /api/v0/* (era propio de LM Studio) -> ver `ctx` y `bench`
#   - un id de modelo que no existe da 404, no un fallback silencioso
SWAP_URL := http://pcgamer:1234

# mcporter: version FIJADA en mcporter/pin.json (no @latest: dos maquinas
# instaladas en fechas distintas acabarian con versiones distintas).
MCPORTER_PIN := $(shell python3 -c "import json;print(json.load(open('$(REPO_DIR)/mcporter/pin.json'))['mcporter'])" 2>/dev/null)

.DEFAULT_GOAL := help

## help: Muestra esta ayuda
.PHONY: help
help:
	@echo "opencode-config — targets disponibles:"
	@echo ""
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /'
	@echo ""
	@echo "Repo:    $(REPO_DIR)"
	@echo "Target:  $(TARGET_DIR)"

## install: Symlinks de la config de opencode (respalda lo existente) + gh. mcporter/MCP van aparte: make mcporter
.PHONY: install
install: backup links gh

## links: Solo los symlinks ~/.config/opencode/* -> este repo
.PHONY: links
links:
	@mkdir -p "$(TARGET_DIR)"
	@for item in $(LINKS); do \
		src="$(REPO_DIR)/$$item"; \
		dst="$(TARGET_DIR)/$$item"; \
		if [ -L "$$dst" ]; then rm -f "$$dst"; \
		elif [ -e "$$dst" ]; then rm -rf "$$dst"; fi; \
		ln -s "$$src" "$$dst"; \
		echo "  linked  $$dst -> $$src"; \
	done
	@echo "✅ symlinks listos."

## uninstall: Elimina solo los symlinks creados por este repo
.PHONY: uninstall
uninstall:
	@for item in $(LINKS); do \
		dst="$(TARGET_DIR)/$$item"; \
		if [ -L "$$dst" ]; then rm -f "$$dst"; echo "  unlinked $$dst"; \
		else echo "  skip (no symlink) $$dst"; fi; \
	done
	@echo "ℹ️  Restaura un respaldo con: make restore"

## backup: Respalda los archivos actuales de ~/.config/opencode (si no son symlinks)
.PHONY: backup
backup:
	@created=0; \
	for item in $(LINKS); do \
		dst="$(TARGET_DIR)/$$item"; \
		if [ -e "$$dst" ] && [ ! -L "$$dst" ]; then \
			mkdir -p "$(BACKUP_DIR)/$(STAMP)"; \
			cp -a "$$dst" "$(BACKUP_DIR)/$(STAMP)/"; \
			echo "  backup  $$dst -> $(BACKUP_DIR)/$(STAMP)/"; \
			created=1; \
		fi; \
	done; \
	[ $$created -eq 0 ] && echo "  (nada que respaldar; ya son symlinks o no existen)" || true

## restore: Restaura el ultimo respaldo sobre ~/.config/opencode
.PHONY: restore
restore:
	@last=$$(ls -1dt "$(BACKUP_DIR)"/*/ 2>/dev/null | head -1); \
	if [ -z "$$last" ]; then echo "No hay respaldos en $(BACKUP_DIR)"; exit 1; fi; \
	echo "Restaurando desde $$last"; \
	for item in $(LINKS); do \
		dst="$(TARGET_DIR)/$$item"; \
		if [ -e "$$last/$$item" ]; then \
			if [ -L "$$dst" ]; then rm -f "$$dst"; else rm -rf "$$dst"; fi; \
			cp -a "$$last/$$item" "$$dst"; \
			echo "  restored $$dst"; \
		fi; \
	done

## status: Muestra el estado de los symlinks
.PHONY: status
status:
	@for item in $(LINKS); do \
		dst="$(TARGET_DIR)/$$item"; \
		if [ -L "$$dst" ]; then printf "  \033[32m●\033[0m %-16s -> %s\n" "$$item" "$$(readlink "$$dst")"; \
		elif [ -e "$$dst" ]; then printf "  \033[33m○\033[0m %-16s (archivo real, no symlink)\n" "$$item"; \
		else printf "  \033[31m✗\033[0m %-16s (no existe)\n" "$$item"; fi; \
	done

## test-conn: Verifica conectividad con el server de modelos en pcgamer
.PHONY: test-conn
test-conn:
	@echo "Probando $(SWAP_URL) ..."
	@curl -s -m 5 "$(SWAP_URL)/v1/models" >/dev/null && echo "✅ llama-swap responde" || echo "❌ Sin respuesta (revisa Tailscale / llama-swap en pcgamer)"

## init-agents: Genera un AGENTS.md en el proyecto actual (DIR=. por defecto)
.PHONY: init-agents
init-agents:
	@bash "$(REPO_DIR)/bin/init-agents.sh" "$(if $(DIR),$(DIR),$(CURDIR))"

## clis: mcporter + gh (atajo: make mcporter gh)
.PHONY: clis
clis: mcporter gh

## mcporter: Instala mcporter (todos los MCP por bash) y enlaza el catalogo; NO autentica nada
.PHONY: mcporter
mcporter:
	@# Una sola via para integraciones: MCP a traves de mcporter + bin/mcp.sh.
	@# opencode.jsonc lleva `mcp: {}` a proposito: un MCP declarado ahi mete su
	@# esquema en CADA turno (Notion: 4370 tok solo lectura). Por mcp.sh cuesta 0
	@# hasta que se usa. Autenticar es aparte y por servidor: mcporter auth <s>.
	@# Se instala la version del pin, ni mas ni menos: asi todas las maquinas
	@# corren la misma. mcp.sh detecta capacidades igualmente, por si acaso.
	@test -n "$(MCPORTER_PIN)" || { echo "  ❌ no puedo leer mcporter/pin.json"; exit 1; }
	@have=$$(command -v mcporter >/dev/null 2>&1 && mcporter --version </dev/null 2>/dev/null || echo ""); \
	if [ "$$have" = "$(MCPORTER_PIN)" ]; then \
		echo "  ✅ mcporter $$have (= pin del repo)"; \
	elif command -v npm >/dev/null 2>&1; then \
		[ -n "$$have" ] && echo "  mcporter $$have != pin $(MCPORTER_PIN): fijando..." || echo "  instalando mcporter $(MCPORTER_PIN)..."; \
		npm install --global mcporter@$(MCPORTER_PIN) >/dev/null 2>&1 && echo "  ✅ mcporter $$(mcporter --version </dev/null 2>/dev/null)" || { echo "  ❌ npm no pudo instalar mcporter@$(MCPORTER_PIN)"; exit 1; }; \
	else \
		echo "  ❌ falta npm (Node 22+): npm i -g mcporter@$(MCPORTER_PIN)"; exit 1; \
	fi
	@mkdir -p "$(HOME)/.mcporter"; ln -sfn "$(REPO_DIR)/mcporter/mcporter.json" "$(HOME)/.mcporter/mcporter.json"; \
	echo "  linked  $(HOME)/.mcporter/mcporter.json -> $(REPO_DIR)/mcporter/mcporter.json"
	@$(MAKE) --no-print-directory mcp-status

## gh: GitHub CLI (herramienta de desarrollo, no una integracion)
.PHONY: gh
gh:
	@if command -v gh >/dev/null 2>&1; then \
		echo "  ✅ gh $$(gh --version 2>/dev/null | head -1 | awk '{print $$3}') ya instalado"; \
	elif command -v brew >/dev/null 2>&1; then \
		echo "  instalando gh (GitHub CLI) con Homebrew..."; \
		brew install gh && echo "  ✅ gh instalado"; \
	else \
		echo "  ❌ falta Homebrew: instala gh a mano -> https://cli.github.com"; \
	fi
	@gh auth status >/dev/null 2>&1 && echo "  ✅ gh: GitHub autenticado" || echo "  ○ gh: sin autenticar ->  gh auth login"

## mcporter_bump: Sube el pin de mcporter a la ultima version, lo escribe en mcporter/pin.json y corre los tests
.PHONY: mcporter_bump
mcporter_bump:
	@command -v npm >/dev/null 2>&1 || { echo "  ❌ falta npm"; exit 1; }
	@npm install --global mcporter@latest >/dev/null 2>&1 || { echo "  ❌ npm fallo"; exit 1; }
	@new=$$(mcporter --version </dev/null 2>/dev/null); \
	python3 -c "import json,sys;p='$(REPO_DIR)/mcporter/pin.json';d=json.load(open(p));old=d['mcporter'];d['mcporter']=sys.argv[1];json.dump(d,open(p,'w'),indent=2,ensure_ascii=False);open(p,'a').write('\n');print(f'  pin {old} -> {sys.argv[1]}')" "$$new"
	@rm -rf "$${TMPDIR:-/tmp}/mcp-sh-cache"
	@$(MAKE) --no-print-directory test-plugins
	@echo "  Si los tests pasan, commitea mcporter/pin.json para que las demas maquinas usen esta version."

## versions: Versiones instaladas vs las que fija/registra mcporter/pin.json
.PHONY: versions
versions:
	@pin="$(REPO_DIR)/mcporter/pin.json"; \
	for t in mcporter gh herdr opencode node; do \
		have=$$(command -v $$t >/dev/null 2>&1 && $$t --version </dev/null 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "-"); \
		want=$$(python3 -c "import json,sys;d=json.load(open('$$pin'));print(d.get(sys.argv[1]) or (d.get('reference') or {}).get(sys.argv[1]) or '-')" $$t); \
		kind=$$(python3 -c "import json,sys;d=json.load(open('$$pin'));print('pin' if sys.argv[1] in d else 'ref')" $$t); \
		if [ "$$have" = "$$want" ]; then mark="✅"; elif [ "$$kind" = "pin" ]; then mark="❌"; else mark="○ "; fi; \
		printf "  %s %-10s instalada=%-10s %s=%s\n" "$$mark" "$$t" "$$have" "$$kind" "$$want"; \
	done
	@echo "  pin = se instala exactamente esa (make mcporter) · ref = ultima verificada, informativa"

## memory_vectors: Instala el embedder local (venv con fastembed, ~400MB) para la busqueda por significado; opcional
.PHONY: memory_vectors
memory_vectors:
	@# Tercer nivel de la memoria: solo se usa cuando palabras+sinonimos y FTS5
	@# no encuentran nada, porque arrancar el runtime cuesta 1-3 s. El venv vive
	@# FUERA del repo (no se versionan 400 MB) y es 100% opcional.
	@v="$${MEMORY_VENV:-$(HOME)/.cache/opencode-memory-venv}"; \
	if [ -x "$$v/bin/python" ]; then echo "  ✅ embedder ya instalado en $$v"; \
	else \
		echo "  creando venv en $$v ..."; \
		python3 -m venv "$$v" && "$$v/bin/pip" install -q fastembed && echo "  ✅ fastembed instalado"; \
	fi
	@MEMORY_VENV="$${MEMORY_VENV:-$(HOME)/.cache/opencode-memory-venv}" OPENCODE_MEMORY_DIR="$(REPO_DIR)/memory" python3 "$(REPO_DIR)/bin/_memory_index.py" embed
	@MEMORY_VENV="$${MEMORY_VENV:-$(HOME)/.cache/opencode-memory-venv}" OPENCODE_MEMORY_DIR="$(REPO_DIR)/memory" python3 "$(REPO_DIR)/bin/_memory_index.py" stats

## memory_status: Estado del indice de memoria (entradas, embeddings, umbral)
.PHONY: memory_status
memory_status:
	@OPENCODE_MEMORY_DIR="$(REPO_DIR)/memory" python3 "$(REPO_DIR)/bin/_memory_index.py" stats
	@OPENCODE_MEMORY_DIR="$(REPO_DIR)/memory" bash "$(REPO_DIR)/bin/memory.sh" check

## mcp-snapshot: Guarda en el repo el esquema de las tools de los servidores autenticados (para que `tools`/`describe` funcionen sin sesion)
.PHONY: mcp-snapshot
mcp-snapshot:
	@MCP_CATALOG="$(HOME)/.mcporter/mcporter.json" python3 "$(REPO_DIR)/bin/_mcp.py" snapshot

## mcp-status: Servidores MCP del catalogo: cuales tienen sesion guardada (lectura LOCAL; nunca abre el navegador)
.PHONY: mcp-status
mcp-status:
	@MCP_CATALOG="$(REPO_DIR)/mcporter/mcporter.json" python3 "$(REPO_DIR)/bin/_mcp.py" status

## mcp-check: Conecta de verdad a cada servidor (sin OAuth) y dice cuantas tools expone
.PHONY: mcp-check
mcp-check:
	@command -v mcporter >/dev/null 2>&1 || { echo "  mcporter no instalado (make mcporter)"; exit 0; }
	@MCP_CATALOG="$(REPO_DIR)/mcporter/mcporter.json" python3 "$(REPO_DIR)/bin/_mcp.py" check

## bench-models: Compara modelos con las 4 tareas objetivas (MODEL=... TAG=... AGENT=... para uno solo)
.PHONY: bench-models
bench-models:
	@if [ -n "$(MODEL)" ]; then \
		bash "$(REPO_DIR)/bench/run-model.sh" "$(MODEL)" "$(if $(TAG),$(TAG),custom)" "$(AGENT)"; \
	else \
		bash "$(REPO_DIR)/bench/run-model.sh" local/qwen-35b qwen35; \
		bash "$(REPO_DIR)/bench/run-model.sh" local/qwen-9b qwen9; \
	fi
	@echo ""
	@for t in redtest newproj lookup ticket; do \
		for d in "$(REPO_DIR)"/bench/*-$$t; do \
			[ -d "$$d" ] || continue; \
			printf "  %-22s %5ss  %s\n" "$$(basename $$d)" "$$(cat $$d/.seconds 2>/dev/null)" "$$(bash "$(REPO_DIR)/bench/score.sh" $$t $$d)"; \
		done; \
	done

## test-plugins: Tests de los plugins que pueden bloquear al agente
.PHONY: test-plugins
test-plugins:
	@node --experimental-strip-types "$(REPO_DIR)/test/plugins.mjs" 2>&1 | grep -v "ExperimentalWarning\|--experimental\|^(node:"

## ctx: Contexto REAL de lo cargado vs. el declarado en opencode.jsonc
.PHONY: ctx
ctx:
	@# llama-swap no tiene /api/v0/models (eso era LM Studio). El n_ctx real es
	@# el `-c` de la linea de comandos de llama.cpp, que /running expone tal cual.
	@curl -s -m 5 "$(SWAP_URL)/running" | python3 -c "\
import sys,json,re;\
r=json.load(sys.stdin).get('running',[]);\
[print(f\"  cargado  : {m['model']:14} -c {(re.search(r'-c (\\d+)', m['cmd']) or [None,'?'])[1]:>7}  ({m['state']})\") for m in r] or print('  (ningun modelo cargado)')" 2>/dev/null || echo "  ❌ sin respuesta"
	@python3 -c "\
import re,json;\
s=open('$(REPO_DIR)/opencode.jsonc').read();\
s=re.sub(r'^\s*//.*\$$','',s,flags=re.M);\
c=json.loads(s)['provider']['local']['models'];\
[print(f\"  declarado: {k:14} context={v['limit']['context']}  output={v['limit']['output']}  -> compacta a los {v['limit']['context']-min(v['limit']['output'],32000)} tokens\") for k,v in c.items()]"
	@echo "  Regla: context <= -c, y deja ~3k de colchon. Pasarse no da error: trunca."

## bench: Mide tokens/seg contra el modelo cargado
.PHONY: bench
bench:
	@# llama.cpp devuelve un objeto `timings` en la respuesta OpenAI-compatible.
	@# Ahi esta el dato bueno; el /api/v0/... de LM Studio ya no existe.
	@m=$$(curl -s -m 5 "$(SWAP_URL)/running" | python3 -c "import sys,json;r=json.load(sys.stdin).get('running',[]);print(r[0]['model'] if r else '')"); \
	if [ -z "$$m" ]; then echo "  ❌ ningun modelo cargado (pide uno con: make bench MODEL=qwen-35b)"; exit 0; fi; \
	echo "  modelo: $$m"; \
	curl -s -m 180 "$(SWAP_URL)/v1/chat/completions" -H 'Content-Type: application/json' \
		-d "{\"model\":\"$$m\",\"messages\":[{\"role\":\"system\",\"content\":\"You are a helpful assistant.\"},{\"role\":\"user\",\"content\":\"Count from 1 to 60, one number per line.\"}],\"max_tokens\":200,\"temperature\":0.1}" \
		| python3 -c "\
import sys,json;\
d=json.load(sys.stdin);t=d.get('timings',{});\
print(f\"  {t.get('predicted_per_second',0):.1f} tok/s  (prompt {t.get('prompt_per_second',0):.1f} tok/s, draft {t.get('draft_n_accepted','-')}/{t.get('draft_n','-')} aceptados)\")" 2>/dev/null || echo "  ❌ sin respuesta"

## models: Lista los modelos que llama-swap expone (y cual esta cargado)
.PHONY: models
models:
	@# Estos ids son la VERDAD. Lo que pongas en opencode.jsonc tiene que salir
	@# aqui tal cual: si no, opencode recibe 404 "no router for requested model".
	@curl -s -m 5 "$(SWAP_URL)/v1/models" | python3 -c "\
import sys,json;\
[print(f\"  - {m['id']:14} {m.get('status',{}).get('value','?')}\") for m in json.load(sys.stdin)['data']]" 2>/dev/null || echo "❌ No se pudo consultar modelos"
	@python3 -c "\
import re,json;\
s=re.sub(r'^\s*//.*\$$','',open('$(REPO_DIR)/opencode.jsonc').read(),flags=re.M);\
d=json.loads(s);\
print('  declarados en opencode.jsonc:', ', '.join(d['provider']['local']['models']));\
print('  model =', d['model'], '| small_model =', d['small_model'])"
