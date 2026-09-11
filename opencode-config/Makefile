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
LINKS        := opencode.jsonc agent rules command plugin bin templates skill

# Endpoint del PC con los modelos: llama-swap delante de llama.cpp, via
# Tailscale. NO es LM Studio (lo fue). Se nota en dos sitios:
#   - no existe /api/v0/* (era propio de LM Studio) -> ver `ctx` y `bench`
#   - un id de modelo que no existe da 404, no un fallback silencioso
SWAP_URL := http://pcgamer:1234

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

## install: Crea los symlinks (respalda lo existente primero)
.PHONY: install
install: backup
	@mkdir -p "$(TARGET_DIR)"
	@for item in $(LINKS); do \
		src="$(REPO_DIR)/$$item"; \
		dst="$(TARGET_DIR)/$$item"; \
		if [ -L "$$dst" ]; then rm -f "$$dst"; \
		elif [ -e "$$dst" ]; then rm -rf "$$dst"; fi; \
		ln -s "$$src" "$$dst"; \
		echo "  linked  $$dst -> $$src"; \
	done
	@echo "✅ install completo."

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

## mcp: Estado de los servidores MCP (+ chequeo real de conectividad)
.PHONY: mcp
mcp:
	@opencode mcp list 2>&1 | grep -vE '^\s*$$' || true
	@echo ""
	@echo "  Nota: '✓ connected' = el proceso arranca y hace handshake."
	@echo "        NO garantiza que sus herramientas devuelvan datos."
	@python3 -c "\
import re,json,urllib.request,sys;\
s=re.sub(r'^\s*//.*$$','',open('$(REPO_DIR)/opencode.jsonc').read(),flags=re.M);\
m=json.loads(s).get('mcp') or {};\
[print(f\"  {k}: declarado enabled={v.get('enabled', True)}\" + (' (remoto: ' + v['url'] + ')' if v.get('type')=='remote' else '')) for k,v in m.items()]"
	@for u in $$(python3 -c "import re,json;s=re.sub(r'^\s*//.*$$','',open('$(REPO_DIR)/opencode.jsonc').read(),flags=re.M);[print(v['url']) for v in (json.loads(s).get('mcp') or {}).values() if v.get('type')=='remote' and v.get('enabled',True)]"); do 		code=$$(curl -s -m 3 -o /dev/null -w '%{http_code}' "$$u" 2>/dev/null); 		if [ "$$code" = "000" ]; then echo "  ❌ $$u no responde — ¿esta levantado el servidor?"; 		else echo "  ✅ $$u responde (HTTP $$code)"; fi; 	done

## bench-models: Compara modelos con las 4 tareas objetivas (MODEL=... TAG=... AGENT=... para uno solo)
.PHONY: bench-models
bench-models:
	@if [ -n "$(MODEL)" ]; then \
		bash "$(REPO_DIR)/bench/run-model.sh" "$(MODEL)" "$(if $(TAG),$(TAG),custom)" "$(AGENT)"; \
	else \
		bash "$(REPO_DIR)/bench/run-model.sh" lmstudio/qwen-35b qwen35; \
		bash "$(REPO_DIR)/bench/run-model.sh" lmstudio/qwen-9b qwen9; \
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
c=json.loads(s)['provider']['lmstudio']['models'];\
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
print('  declarados en opencode.jsonc:', ', '.join(d['provider']['lmstudio']['models']));\
print('  model =', d['model'], '| small_model =', d['small_model'])"
