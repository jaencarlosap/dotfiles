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
LINKS        := opencode.jsonc agent

# Endpoint del PC con los modelos (LM Studio via Tailscale)
LMSTUDIO_URL := http://pcgamer:1234/v1

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

## test-conn: Verifica conectividad con LM Studio en pcgamer
.PHONY: test-conn
test-conn:
	@echo "Probando $(LMSTUDIO_URL) ..."
	@curl -s -m 5 "$(LMSTUDIO_URL)/models" >/dev/null && echo "✅ LM Studio responde" || echo "❌ Sin respuesta (revisa Tailscale / LM Studio server)"

## models: Lista los modelos disponibles en pcgamer
.PHONY: models
models:
	@curl -s -m 5 "$(LMSTUDIO_URL)/models" | python3 -c "import sys,json; [print('  -', m['id']) for m in json.load(sys.stdin)['data']]" 2>/dev/null || echo "❌ No se pudo consultar modelos"
