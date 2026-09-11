#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# init-agents — crea un AGENTS.md en el proyecto ACTUAL a partir de la
# plantilla, con los comandos de build/test/lint ya rellenados segun el
# tipo de proyecto detectado. opencode carga AGENTS.md automaticamente.
#
# Uso:  cd tu-proyecto && ~/.config/opencode/bin/init-agents.sh
#       (o:  make -C ~/dotfiles/opencode-config init-agents DIR="$PWD")
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

DEST_DIR="${1:-$PWD}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../templates/AGENTS.md"
DEST="$DEST_DIR/AGENTS.md"

[ -f "$TEMPLATE" ] || { echo "❌ No encuentro la plantilla: $TEMPLATE"; exit 1; }

if [ -e "$DEST" ]; then
  echo "ℹ️  Ya existe $DEST — no lo sobrescribo. Editalo a mano."
  exit 0
fi

# Detecta el tipo de proyecto y fija los comandos.
build="<!-- build command -->"; test="<!-- test command -->"; lint="<!-- lint/format command -->"
if   [ -f "$DEST_DIR/go.mod" ]; then
  build="go build ./..."; test="go test ./..."; lint="gofmt -l . && go vet ./..."
elif [ -f "$DEST_DIR/Cargo.toml" ]; then
  build="cargo build"; test="cargo test"; lint="cargo fmt --check && cargo clippy"
elif [ -f "$DEST_DIR/package.json" ]; then
  pm="npm"; [ -f "$DEST_DIR/bun.lock" ] || [ -f "$DEST_DIR/bun.lockb" ] && pm="bun"
  [ -f "$DEST_DIR/pnpm-lock.yaml" ] && pm="pnpm"
  [ -f "$DEST_DIR/yarn.lock" ] && pm="yarn"
  build="$pm run build"; test="$pm test"; lint="$pm run lint"
elif [ -f "$DEST_DIR/pyproject.toml" ] || [ -f "$DEST_DIR/setup.py" ]; then
  build="python -m build"; test="pytest -q"; lint="ruff check ."
fi

# Escapa los caracteres especiales de la parte de REEMPLAZO de sed:
#   \  -> literal,   |  -> es el delimitador,   &  -> "todo lo casado".
# Sin esto, un comando de lint con `&&` (p.ej. gofmt && go vet) se corrompe.
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

sed -e "s|__BUILD__|$(esc "$build")|" \
    -e "s|__TEST__|$(esc "$test")|" \
    -e "s|__LINT__|$(esc "$lint")|" \
    "$TEMPLATE" > "$DEST"

echo "✅ Creado $DEST"
echo "   build: $build"
echo "   test:  $test"
echo "   Rellena las secciones <!-- ... --> con lo especifico del proyecto."
