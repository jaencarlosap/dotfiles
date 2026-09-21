.PHONY: help setup setup_dry dtool_release install_nvim clean_system clean_system_dry clean_disk clean_disk_dry clean_disk_sudo \
	dtool install_dtool install_opencode uninstall_opencode opencode_status \
	install_herdr uninstall_herdr herdr_status

.DEFAULT_GOAL := help

## help: Lista los targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /'

# dtool viene COMPILADO en el repo (dtool/bin/dtool-<os>-<arch>) para que una
# maquina nueva no necesite Go ni descargar nada: `make setup` elige el binario
# por `uname`. `make dtool` compila el local (desarrollo) y `make dtool_release`
# regenera los tres binarios versionados tras tocar dtool/.
DTOOL_OS   := $(shell uname -s | tr '[:upper:]' '[:lower:]')
DTOOL_ARCH := $(shell uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')
DTOOL_BIN  := dtool/bin/dtool-$(DTOOL_OS)-$(DTOOL_ARCH)

## setup: Instalador interactivo (dtool precompilado): elige que instalar, que autenticar (gh, cada MCP) y que ejecutar, en orden
setup:
	@test -x "$(DTOOL_BIN)" || { echo "no hay binario para $(DTOOL_OS)/$(DTOOL_ARCH) en dtool/bin/; con Go: make dtool && ./dtool/dtool --page installer"; exit 1; }
	@"$(DTOOL_BIN)" --page installer

## setup_dry: El instalador sin ejecutar nada (lista los comandos que correria)
setup_dry:
	@test -x "$(DTOOL_BIN)" || { echo "no hay binario para $(DTOOL_OS)/$(DTOOL_ARCH) en dtool/bin/"; exit 1; }
	@"$(DTOOL_BIN)" --page installer --dry-run

## dtool_release: Recompila los binarios versionados (darwin amd64/arm64, linux amd64) — correr tras cambiar dtool/
dtool_release:
	@cd dtool && for t in darwin/amd64 darwin/arm64 linux/amd64; do \
		CGO_ENABLED=0 GOOS=$${t%/*} GOARCH=$${t#*/} go build -trimpath -ldflags="-s -w" -o bin/dtool-$${t%/*}-$${t#*/} . && echo "  built dtool/bin/dtool-$${t%/*}-$${t#*/}"; done

# Los scripts de shell viven en scripts/ y son los que usan estos targets.
# dtool/ (TUI en Go) es la version interactiva de los mismos flujos, no un
# reemplazo: los scripts son los que se pueden lanzar desde make, cron o un
# agente.

## install_nvim: Instala Xcode CLT / Homebrew / neovim si faltan y enlaza nvim-config (YES=1 sin preguntas)
install_nvim:
	@YES="$(YES)" bash scripts/setup_nvim.sh

## clean_system: Limpieza de macOS INTERACTIVA (menu; se bloquea si no hay teclado)
clean_system:
	@bash scripts/clean_system.sh

## clean_system_dry: El menu interactivo en modo simulacion
clean_system_dry:
	@bash scripts/clean_system.sh --dry-run

## clean_disk: Limpieza de disco SIN preguntas: caches de usuario, Go, npm/pnpm/yarn/pip/brew/cargo, Docker (sin volumenes), updaters, ~/.cache
clean_disk:
	@# Lo que se corrio el 2026-09-19: de 5.5 GB libres a 42 GB. Todo es
	@# re-descargable. Docker.raw solo encoge al reiniciar Docker Desktop.
	@df -h / | tail -1 | awk '{print "  disco antes: " $$4 " libres de " $$2}'
	@bash scripts/clean_system.sh --yes --only user
	@df -h / | tail -1 | awk '{print "  disco despues: " $$4 " libres de " $$2}'

## clean_disk_dry: Lo mismo que clean_disk pero solo muestra tamanos, no borra
clean_disk_dry:
	@bash scripts/clean_system.sh --dry-run --only user

## clean_disk_sudo: La parte que requiere root: caches de sistema, /private/tmp, DNS
clean_disk_sudo:
	@sudo bash scripts/clean_system.sh --yes --only sudo

dtool:
	cd dtool && go build -o dtool .

install_dtool:
	mkdir -p $(HOME)/.local/bin
	cp "$(DTOOL_BIN)" $(HOME)/.local/bin/dtool
	@echo "Installed to $(HOME)/.local/bin/dtool — make sure that dir is on your PATH."

# herdr: runtime persistente para los agentes (tmux para agentes). Binario por
# su instalador oficial (https://herdr.dev/install.sh -> ~/.local/bin/herdr) y
# actualizaciones con `herdr update`. NO por Homebrew: en este Mac no hay
# bottle y brew intenta compilar Rust entero desde fuente (horas; se probo el
# 2026-09-19 y se aborto). Config versionada en herdr-config/ -> ~/.config/herdr.
# Solo se enlaza config.toml: en ~/.config/herdr viven ademas sockets, logs y
# session.json, que no son del repo.
HERDR_CFG := $(HOME)/.config/herdr

## install_herdr: Instala herdr (instalador oficial), enlaza herdr-config/config.toml, integra opencode y claude, valida la config
install_herdr:
	@if command -v herdr >/dev/null 2>&1; then echo "  ✅ herdr $$(herdr --version | awk '{print $$2}') ya instalado (actualizar: herdr update)"; \
	else curl -fsSL https://herdr.dev/install.sh | sh && echo "  ✅ herdr instalado en ~/.local/bin"; fi
	@mkdir -p "$(HERDR_CFG)"
	@if [ -e "$(HERDR_CFG)/config.toml" ] && [ ! -L "$(HERDR_CFG)/config.toml" ]; then \
		cp "$(HERDR_CFG)/config.toml" "$(HERDR_CFG)/config.toml.bak-$$(date +%Y%m%d-%H%M%S)"; echo "  respaldo de la config previa en $(HERDR_CFG)/config.toml.bak-*"; fi
	@ln -sfn "$(CURDIR)/herdr-config/config.toml" "$(HERDR_CFG)/config.toml"
	@echo "  linked  $(HERDR_CFG)/config.toml -> $(CURDIR)/herdr-config/config.toml"
	@# Integraciones: solo OBSERVAN (estado idle/blocked/done por socket), no tocan
	@# args ni salidas de tools, asi que no chocan con los plugins de opencode-config.
	@herdr integration install opencode >/dev/null 2>&1 && echo "  ✅ integracion opencode" || echo "  ⚠️  integracion opencode: fallo (herdr integration install opencode)"
	@herdr integration install claude   >/dev/null 2>&1 && echo "  ✅ integracion claude"   || echo "  ⚠️  integracion claude: fallo"
	@herdr config check 2>&1 | sed 's/^/  /'
	@herdr server reload-config >/dev/null 2>&1 && echo "  ✅ config recargada en el servidor" || echo "  ℹ️  servidor parado: la config se lee al arrancar (herdr)"

## herdr_status: Cliente/servidor, integraciones y como entrar desde el movil
herdr_status:
	@herdr status 2>&1 | sed 's/^/  /'
	@herdr integration status 2>&1 | grep -E "opencode|claude" | sed 's/^/  /'
	@echo ""
	@ts="$$(command -v tailscale || echo /Applications/Tailscale.app/Contents/MacOS/Tailscale)"; \
	host="$$($$ts status --self 2>/dev/null | awk 'NR==1{print $$2}')"; host="$${host:-$$(scutil --get LocalHostName).local}"; \
	echo "  Desde el movil (cliente SSH, p.ej. Termius): ssh $$(whoami)@$$host   y luego:  herdr"; \
	echo "  Desde otro Mac/Linux con herdr:                 herdr --remote $$(whoami)@$$host"

## uninstall_herdr: Quita el symlink de la config (deja el binario y las integraciones)
uninstall_herdr:
	@[ -L "$(HERDR_CFG)/config.toml" ] && rm "$(HERDR_CFG)/config.toml" && echo "  unlinked $(HERDR_CFG)/config.toml" || echo "  (no era symlink)"

# opencode config: symlinks ~/.config/opencode -> opencode-config/ (LM Studio on pcgamer)
install_opencode:
	@$(MAKE) -C opencode-config install

uninstall_opencode:
	@$(MAKE) -C opencode-config uninstall

opencode_status:
	@$(MAKE) -C opencode-config status

