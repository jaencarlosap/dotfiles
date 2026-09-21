#!/usr/bin/env bash
# Idempotent Neovim + LazyVim setup for macOS. Safe to re-run: every step
# checks the current state first and skips what is already done.
#
#   make install_nvim          # interactive (asks before installing Homebrew)
#   make install_nvim YES=1    # non-interactive
#
# What it does, in order:
#   1. Xcode Command Line Tools   (git + a C compiler; treesitter needs both)
#   2. Homebrew                   (installs it if missing)
#   3. Neovim                     (brew on a native /opt/homebrew; otherwise the
#                                  official arm64 release into ~/.local/nvim — see below)
#      brew packages              (ripgrep, fd, lazygit, fzf, node)
#      + tree-sitter CLI via npm  (brew's formula builds rust from source on Intel)
#   4. Hack Nerd Font             (icons in the UI)
#   5. ~/.config/nvim -> nvim-config/   (backs up any real directory it replaces)
#   6. lazy.nvim + plugins        (restored to the versions pinned in lazy-lock.json)
#   7. :checkhealth summary

set -euo pipefail

# Resolve the repo from the script location, NOT from $(pwd): the previous
# version linked "$(pwd)/nvim", a directory that does not exist in this repo.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NVIM_CONFIG_REPO_DIR="$REPO_DIR/nvim-config"
LOCAL_NVIM_DIR="$HOME/.config/nvim"
YES="${YES:-0}"

# Homebrew formulas. `node` is for Copilot and for the tree-sitter CLI below.
# `neovim` is handled separately (it needs a working binary, not a formula).
BREW_PACKAGES=(ripgrep fd lazygit fzf node)
NVIM_RELEASE_URL="https://github.com/neovim/neovim/releases/download/stable/nvim-macos-arm64.tar.gz"
NVIM_LOCAL_DIR="$HOME/.local/nvim"
NERD_FONT_CASK="font-hack-nerd-font"

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '   \033[32m✔\033[0m %s\n' "$*"; }
skip() { printf '   \033[36m•\033[0m %s\n' "$*"; }
warn() { printf '   \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '   \033[31m✖\033[0m %s\n' "$*" >&2; exit 1; }

confirm() {
  [ "$YES" = "1" ] && return 0
  read -r -p "   $1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

[ "$(uname -s)" = "Darwin" ] || die "This script targets macOS (Homebrew). Detected: $(uname -s)"
[ -d "$NVIM_CONFIG_REPO_DIR" ] || die "Config dir not found: $NVIM_CONFIG_REPO_DIR"

# ── 1. Xcode Command Line Tools ──────────────────────────────────────────────
log "Xcode Command Line Tools"
if xcode-select -p >/dev/null 2>&1; then
  ok "installed at $(xcode-select -p)"
else
  warn "not installed — opening the Apple installer (a dialog will appear)."
  xcode-select --install 2>/dev/null || true
  die "Finish the Command Line Tools installation, then run this again."
fi

# ── 2. Homebrew ──────────────────────────────────────────────────────────────
log "Homebrew"
if command -v brew >/dev/null 2>&1; then
  ok "$(brew --version | head -1)"
else
  warn "Homebrew is not installed."
  confirm "Install it with the official script (https://brew.sh)?" || die "Homebrew is required. Install it and re-run."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # The installer does not touch the current shell: put brew on PATH for the
  # rest of this run (Apple Silicon and Intel locations).
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] && eval "$("$b" shellenv)" && break
  done
  command -v brew >/dev/null 2>&1 || die "brew is still not on PATH. Open a new shell and re-run."
  ok "installed"
fi

# ── 3. Neovim ────────────────────────────────────────────────────────────────
# Why not just `brew install neovim`: on an Apple Silicon Mac with Homebrew
# installed at /usr/local (an Intel/Rosetta install) Homebrew no longer ships
# bottles, so every formula compiles from source — and neovim's own deps fail
# to build there. It also breaks silently: a `brew upgrade tree-sitter` moved
# libtree-sitter from 0.26 to 0.27 and the existing nvim stopped starting
# (`dyld: Library not loaded ... libtree-sitter.0.26.dylib`). That is why the
# check below RUNS nvim instead of asking brew whether it is installed.
# The long-term fix is a native Homebrew in /opt/homebrew; until then the
# official arm64 release tarball goes into ~/.local/nvim.
log "Neovim"
if nvim --version >/dev/null 2>&1; then
  ok "$(nvim --version | head -1) at $(command -v nvim)"
elif [ "$(uname -m)" = "arm64" ] && [ "$(brew --prefix)" = "/opt/homebrew" ]; then
  brew install neovim
  ok "$(nvim --version | head -1) (brew)"
else
  if command -v nvim >/dev/null 2>&1; then
    warn "$(command -v nvim) exists but does not start (broken brew build); installing the official release instead"
  fi
  [ "$(uname -m)" = "arm64" ] || die "No bottle for this Homebrew and no arm64 release to fall back to. Install Neovim manually: https://github.com/neovim/neovim/releases"
  tmp="$(mktemp -d)"
  curl -fsSL "$NVIM_RELEASE_URL" | tar xz -C "$tmp"
  rm -rf "$NVIM_LOCAL_DIR"
  mv "$tmp/nvim-macos-arm64" "$NVIM_LOCAL_DIR"
  rm -rf "$tmp"
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$NVIM_LOCAL_DIR/bin/nvim" "$HOME/.local/bin/nvim"
  hash -r 2>/dev/null || true
  "$NVIM_LOCAL_DIR/bin/nvim" --version >/dev/null || die "the downloaded nvim does not run"
  ok "$("$NVIM_LOCAL_DIR/bin/nvim" --version | head -1) installed in $NVIM_LOCAL_DIR"
  if [ "$(command -v nvim || true)" != "$HOME/.local/bin/nvim" ]; then
    warn "~/.local/bin is not ahead of $(dirname "$(command -v nvim || echo /usr/local/bin/x)") in your PATH: add it first, or run brew uninstall neovim"
  fi
fi

# ── 3b. Packages ─────────────────────────────────────────────────────────────
log "Packages: ${BREW_PACKAGES[*]}"
# One `brew list` instead of one per package: it is the slow call.
installed_formulas="$(brew list --formula -1 2>/dev/null)"
to_install=()
for pkg in "${BREW_PACKAGES[@]}"; do
  if grep -qx "$pkg" <<<"$installed_formulas"; then
    skip "$pkg already installed"
  else
    to_install+=("$pkg")
  fi
done
if [ "${#to_install[@]}" -gt 0 ]; then
  brew install "${to_install[@]}"
  ok "installed: ${to_install[*]}"
fi

# The `tree-sitter` brew formula is only the library; the CLI that
# nvim-treesitter needs is `tree-sitter-cli`, and on an Intel-prefix Homebrew
# that formula has no bottle and pulls a from-source rust build (hours). The
# npm package ships the prebuilt binary and takes seconds.
log "tree-sitter CLI (npm)"
if command -v tree-sitter >/dev/null 2>&1; then
  skip "$(tree-sitter --version)"
else
  npm install -g tree-sitter-cli
  ok "$(tree-sitter --version)"
fi

# ── 4. Nerd Font ─────────────────────────────────────────────────────────────
log "Nerd Font ($NERD_FONT_CASK)"
if brew list --cask -1 2>/dev/null | grep -qx "$NERD_FONT_CASK"; then
  skip "already installed"
else
  brew install --cask "$NERD_FONT_CASK"
  ok "installed — select 'Hack Nerd Font' in your terminal profile"
fi

# ── 5. Symlink the config ────────────────────────────────────────────────────
log "Config: $LOCAL_NVIM_DIR -> $NVIM_CONFIG_REPO_DIR"
if [ -L "$LOCAL_NVIM_DIR" ] && [ "$(readlink "$LOCAL_NVIM_DIR")" = "$NVIM_CONFIG_REPO_DIR" ]; then
  skip "already linked"
else
  if [ -L "$LOCAL_NVIM_DIR" ]; then
    rm "$LOCAL_NVIM_DIR"                       # a link elsewhere: just replace it
  elif [ -e "$LOCAL_NVIM_DIR" ]; then
    backup="$LOCAL_NVIM_DIR.bak-$(date +%Y%m%d-%H%M%S)"
    mv "$LOCAL_NVIM_DIR" "$backup"             # a real config: never delete it
    warn "existing config moved to $backup"
  fi
  mkdir -p "$(dirname "$LOCAL_NVIM_DIR")"
  ln -s "$NVIM_CONFIG_REPO_DIR" "$LOCAL_NVIM_DIR"
  ok "linked"
fi

# ── 6. lazy.nvim + plugins ───────────────────────────────────────────────────
# lua/config/lazy.lua clones lazy.nvim itself on first start. `Lazy! restore`
# then installs every plugin at the commit pinned in lazy-lock.json — unlike
# `sync`, it does not silently upgrade everything on a fresh machine.
log "Plugins (lazy.nvim, versions from lazy-lock.json)"
lazy_dir="$HOME/.local/share/nvim/lazy/lazy.nvim"
[ -d "$lazy_dir" ] && skip "lazy.nvim already bootstrapped" || ok "lazy.nvim will be cloned on first start"
# lazy prints one progress line per plugin per task; keep that in a log and
# show it only if the restore fails.
lazy_log="$(mktemp)"
if nvim --headless "+Lazy! restore" +qa >"$lazy_log" 2>&1; then
  ok "plugins restored"
else
  tail -20 "$lazy_log" | sed 's/^/   /'
  die "Lazy restore failed (full log: $lazy_log)"
fi
rm -f "$lazy_log"

# ── 7. Health ────────────────────────────────────────────────────────────────
# Parsers and LSP servers install themselves on the first interactive start;
# this only surfaces what checkhealth still flags after everything above.
log "Health (:checkhealth lazy lazyvim)"
health="$(mktemp)"
nvim --headless -c "checkhealth lazy lazyvim" -c "w! $health" -c "qa!" >/dev/null 2>&1 || true
if grep -qE "ERROR|WARNING" "$health"; then
  grep -E "ERROR|WARNING" "$health" | sed 's/^/   /'
  warn "open nvim and run :checkhealth for details"
else
  ok "no errors or warnings"
fi
rm -f "$health"

log "Done. Start nvim; the first launch installs treesitter parsers and LSP servers."
