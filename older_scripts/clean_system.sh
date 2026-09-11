#!/bin/bash
set -e
set -u

# ============================================
#   macOS System Cleaner v2.0
# ============================================

# ---- Global State ----
DRY_RUN=false
AUTO_YES=false
ONLY=""
TOTAL_FREED_KB=0
INITIAL_FREE_KB=0
IS_ROOT=false

# ---- Parse Arguments ----
show_help() {
  echo "Usage: clean_system.sh [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --dry-run     Show what would be deleted without actually deleting"
  echo "  --yes, -y     Answer yes to every confirmation (non-interactive)"
  echo "  --only LIST   Run these options and skip the menu, e.g. --only 8,11,12"
  echo "  --help, -h    Show this help message"
  echo ""
  echo "Run without sudo for user-level and developer cleanup."
  echo "Run with sudo for system-level operations (system caches, DNS flush, temp files)."
  echo ""
  echo "NOTE: without --only the script is interactive and will BLOCK on a prompt."
  echo "An agent or a cron job must pass --only (and usually --yes), or it hangs."
  echo "The scans that need a human choice (node_modules, venvs) still ask, always."
}

_next_is_only=false
for arg in "${@:-}"; do
  if [ "$_next_is_only" = true ]; then
    ONLY="$arg"; _next_is_only=false; continue
  fi
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --yes|-y)  AUTO_YES=true ;;
    --only)    _next_is_only=true ;;
    --only=*)  ONLY="${arg#--only=}" ;;
    --help|-h) show_help; exit 0 ;;
  esac
done

# ---- Resolve Real User (handle sudo) ----
if [ -n "${SUDO_USER:-}" ]; then
  REAL_USER="$SUDO_USER"
  REAL_HOME=$(eval echo "~$SUDO_USER")
else
  REAL_USER="$(whoami)"
  REAL_HOME="$HOME"
fi

[ "$(id -u)" = "0" ] && IS_ROOT=true

# ---- Trap Ctrl+C ----
trap 'echo ""; echo "  Interrupted. Exiting."; exit 1' INT TERM

# ============================================
#   Utility Functions
# ============================================

get_dir_size_kb() {
  local target="$1"
  if [ -e "$target" ]; then
    du -sk "$target" 2>/dev/null | awk '{print $1}' || echo "0"
  else
    echo "0"
  fi
}

get_free_space_kb() {
  df -k / | tail -1 | awk '{print $4}'
}

human_readable() {
  # Pass the value via -v: nesting escaped quotes inside a command
  # substitution inside double quotes mangles the awk program in bash.
  local kb=$1
  if [ "$kb" -ge 1048576 ]; then
    awk -v k="$kb" 'BEGIN { printf "%.2f GB\n", k / 1048576 }'
  elif [ "$kb" -ge 1024 ]; then
    awk -v k="$kb" 'BEGIN { printf "%.1f MB\n", k / 1024 }'
  else
    echo "${kb} KB"
  fi
}

safe_rm() {
  # Accepts multiple targets: callers pass globs that the shell expands
  # into many words. Handling only "$1" silently left the rest on disk.
  local target
  for target in "$@"; do
    [ -e "$target" ] || continue
    if [ "$DRY_RUN" = true ]; then
      echo "    [DRY RUN] Would delete: $target"
    else
      rm -rf "$target" 2>/dev/null || true
    fi
  done
}

confirm() {
  local prompt="$1"
  if [ "$AUTO_YES" = true ]; then
    echo "$prompt (y/N): y   [--yes]"
    return 0
  fi
  local response
  read -p "$prompt (y/N): " response
  [[ "$response" =~ ^[Yy]$ ]]
}

# Vaciar un directorio SIN expandir un glob.
#
# Por que existe: `rm -rf "$dir"/*` deja el shell expandiendo el glob a un
# argumento por fichero, y con muchos ficheros el exec falla entero con
# "Argument list too long". Como las llamadas de este script iban seguidas de
# `|| true`, el fallo era SILENCIOSO: decia "cleaned" y no habia borrado nada.
#
# Caso real (2026-09-08): ~/.cache/mole tenia 96.786 ficheros. El `rm -rf`
# no borro ni uno y el script lo dio por hecho. `find -delete` no expande nada
# y borra de dentro hacia fuera.
safe_rm_contents() {
  local dir
  for dir in "$@"; do
    [ -d "$dir" ] || continue
    if [ "$DRY_RUN" = true ]; then
      echo "    [DRY RUN] Would empty: $dir ($(ls -1 "$dir" 2>/dev/null | wc -l | tr -d ' ') entries)"
    else
      find "$dir" -mindepth 1 -delete 2>/dev/null || true
    fi
  done
}

confirm_destructive() {
  local prompt="$1"
  local response
  read -p "$prompt Type 'YES' to confirm: " response
  [ "$response" = "YES" ]
}

require_root() {
  if [ "$IS_ROOT" != true ]; then
    echo "  ⚠️  This operation requires root privileges. Re-run with: sudo $0"
    return 1
  fi
}

time_ago() {
  local filepath="$1"
  local mod_epoch
  mod_epoch=$(stat -f %m "$filepath" 2>/dev/null || echo "0")
  local now_epoch
  now_epoch=$(date +%s)
  local diff=$(( now_epoch - mod_epoch ))

  if [ "$diff" -lt 3600 ]; then
    echo "$(( diff / 60 )) minutes ago"
  elif [ "$diff" -lt 86400 ]; then
    echo "$(( diff / 3600 )) hours ago"
  elif [ "$diff" -lt 2592000 ]; then
    echo "$(( diff / 86400 )) days ago"
  elif [ "$diff" -lt 31536000 ]; then
    echo "$(( diff / 2592000 )) months ago"
  else
    echo "$(( diff / 31536000 )) years ago"
  fi
}

# ============================================
#   Cache Cleaning Functions
# ============================================

clean_user_caches() {
  echo ""
  echo "  🔍 Scanning user caches..."

  local targets=(
    "$REAL_HOME/Library/Caches"
    "$REAL_HOME/Library/Application Support/CrashReporter"
    "$REAL_HOME/Library/Containers/*/Data/Library/Caches"
    "$REAL_HOME/Library/Logs"
  )

  local total_kb=0
  for target in "${targets[@]}"; do
    # Handle glob patterns
    for expanded in $target; do
      if [ -e "$expanded" ]; then
        local size_kb
        size_kb=$(get_dir_size_kb "$expanded")
        total_kb=$(( total_kb + size_kb ))
        echo "    $(human_readable "$size_kb")  $expanded"
      fi
    done
  done

  if [ "$total_kb" -eq 0 ]; then
    echo "  ✅ No user caches to clean."
    return 0
  fi

  echo ""
  echo "  Total: $(human_readable "$total_kb")"

  if confirm "  🗑️  Delete user caches?"; then
    for target in "${targets[@]}"; do
      for expanded in $target; do
        if [ -e "$expanded" ]; then
          safe_rm_contents "$expanded"
        fi
      done
    done
    TOTAL_FREED_KB=$(( TOTAL_FREED_KB + total_kb ))
    echo "  ✅ User caches cleaned."
  else
    echo "  ⏭️  Skipped."
  fi
}

clean_system_caches() {
  echo ""
  echo "  🔍 Scanning system caches..."

  if ! require_root; then
    return 0
  fi

  local target="/Library/Caches"
  local size_kb
  size_kb=$(get_dir_size_kb "$target")

  if [ "$size_kb" -eq 0 ]; then
    echo "  ✅ No system caches to clean."
    return 0
  fi

  echo "    $(human_readable "$size_kb")  $target"
  echo ""

  if confirm "  🗑️  Delete system caches?"; then
    safe_rm_contents "$target"
    TOTAL_FREED_KB=$(( TOTAL_FREED_KB + size_kb ))
    echo "  ✅ System caches cleaned."
  else
    echo "  ⏭️  Skipped."
  fi
}

clean_temp_files() {
  echo ""
  echo "  🔍 Scanning temporary files..."

  if ! require_root; then
    return 0
  fi

  local target="/private/tmp"
  local size_kb
  size_kb=$(get_dir_size_kb "$target")

  if [ "$size_kb" -eq 0 ]; then
    echo "  ✅ No temporary files to clean."
    return 0
  fi

  echo "    $(human_readable "$size_kb")  $target"
  echo ""

  if confirm "  🗑️  Delete temporary files?"; then
    safe_rm_contents "$target"
    TOTAL_FREED_KB=$(( TOTAL_FREED_KB + size_kb ))
    echo "  ✅ Temporary files cleaned."
  else
    echo "  ⏭️  Skipped."
  fi
}

flush_dns() {
  echo ""
  echo "  🔄 Flushing DNS cache..."

  if ! require_root; then
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    echo "    [DRY RUN] Would flush DNS cache"
  else
    dscacheutil -flushcache
    killall -HUP mDNSResponder 2>/dev/null || true
  fi

  echo "  ✅ DNS cache flushed."
}

# ============================================
#   Developer Cleanup Functions
# ============================================

prompt_scan_dirs() {
  local defaults=()
  for d in "$REAL_HOME/Documents" "$REAL_HOME/Projects" "$REAL_HOME/Developer" "$REAL_HOME/Desktop" "$REAL_HOME/Code"; do
    [ -d "$d" ] && defaults+=("$d")
  done

  echo "  Default scan directories:"
  for d in "${defaults[@]}"; do
    echo "    - $d"
  done
  echo ""

  local custom_dirs
  read -p "  Enter custom paths (space-separated) or press Enter for defaults: " custom_dirs

  if [ -n "$custom_dirs" ]; then
    SCAN_DIRS=()
    for d in $custom_dirs; do
      if [ -d "$d" ]; then
        SCAN_DIRS+=("$d")
      else
        echo "  ⚠️  Skipping non-existent directory: $d"
      fi
    done
  else
    SCAN_DIRS=("${defaults[@]}")
  fi

  if [ ${#SCAN_DIRS[@]} -eq 0 ]; then
    echo "  ❌ No valid directories to scan."
    return 1
  fi
}

scan_node_modules() {
  echo ""
  echo "  🔍 Scanning for node_modules directories..."
  echo ""

  if ! prompt_scan_dirs; then
    return 0
  fi

  echo ""
  echo "  🔄 Searching (this may take a moment)..."

  local found=()
  local sizes=()
  local times=()

  for dir in "${SCAN_DIRS[@]}"; do
    while IFS= read -r nm_dir; do
      [ -z "$nm_dir" ] && continue
      local size_kb
      size_kb=$(get_dir_size_kb "$nm_dir")
      local parent_dir
      parent_dir=$(dirname "$nm_dir")
      local mod_time
      if [ -f "$parent_dir/package.json" ]; then
        mod_time=$(time_ago "$parent_dir/package.json")
      else
        mod_time=$(time_ago "$nm_dir")
      fi

      found+=("$nm_dir")
      sizes+=("$size_kb")
      times+=("$mod_time")
    done < <(find "$dir" -maxdepth 6 -name "node_modules" -type d -prune 2>/dev/null)
  done

  if [ ${#found[@]} -eq 0 ]; then
    echo "  ✅ No node_modules directories found."
    return 0
  fi

  # Sort by size (largest first) using indices
  local indices=()
  for i in "${!found[@]}"; do
    indices+=("$i")
  done

  IFS=$'\n' sorted_indices=($(for i in "${indices[@]}"; do echo "$i ${sizes[$i]}"; done | sort -k2 -rn | awk '{print $1}'))
  unset IFS

  echo ""
  printf "  %-4s %-12s %-20s %s\n" "#" "Size" "Last Modified" "Path"
  echo "  ──── ──────────── ──────────────────── ──────────────────────────────"

  local count=1
  local display_map=()
  for idx in "${sorted_indices[@]}"; do
    display_map+=("$idx")
    printf "  %-4s %-12s %-20s %s\n" "$count)" "$(human_readable "${sizes[$idx]}")" "${times[$idx]}" "${found[$idx]}"
    count=$(( count + 1 ))
  done

  echo ""
  local selection
  read -p "  Enter numbers to delete (comma-separated), 'a' for all, or 'n' to skip: " selection

  if [ "$selection" = "n" ] || [ -z "$selection" ]; then
    echo "  ⏭️  Skipped."
    return 0
  fi

  local to_delete=()
  local delete_size_kb=0

  if [ "$selection" = "a" ]; then
    for idx in "${display_map[@]}"; do
      to_delete+=("${found[$idx]}")
      delete_size_kb=$(( delete_size_kb + sizes[$idx] ))
    done
  else
    IFS=',' read -ra nums <<< "$selection"
    for num in "${nums[@]}"; do
      num=$(echo "$num" | tr -d ' ')
      if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#display_map[@]} ]; then
        local real_idx="${display_map[$(( num - 1 ))]}"
        to_delete+=("${found[$real_idx]}")
        delete_size_kb=$(( delete_size_kb + sizes[$real_idx] ))
      else
        echo "  ⚠️  Invalid selection: $num"
      fi
    done
  fi

  if [ ${#to_delete[@]} -eq 0 ]; then
    echo "  ⏭️  Nothing selected."
    return 0
  fi

  echo ""
  echo "  Will delete ${#to_delete[@]} node_modules directories ($(human_readable "$delete_size_kb"))."

  if confirm_destructive "  🗑️  Delete selected node_modules?"; then
    for dir in "${to_delete[@]}"; do
      echo "    🗑️  Deleting $dir..."
      safe_rm "$dir"
    done
    TOTAL_FREED_KB=$(( TOTAL_FREED_KB + delete_size_kb ))
    echo "  ✅ node_modules cleanup complete."
  else
    echo "  ⏭️  Cancelled."
  fi
}

scan_python_venvs() {
  echo ""
  echo "  🔍 Scanning for Python virtual environments..."
  echo ""

  if ! prompt_scan_dirs; then
    return 0
  fi

  echo ""
  echo "  🔄 Searching (this may take a moment)..."

  local found=()
  local sizes=()
  local times=()

  for dir in "${SCAN_DIRS[@]}"; do
    while IFS= read -r venv_dir; do
      [ -z "$venv_dir" ] && continue
      # Only include directories that contain pyvenv.cfg (real Python venvs)
      if [ -f "$venv_dir/pyvenv.cfg" ]; then
        local size_kb
        size_kb=$(get_dir_size_kb "$venv_dir")
        local mod_time
        mod_time=$(time_ago "$venv_dir/pyvenv.cfg")

        found+=("$venv_dir")
        sizes+=("$size_kb")
        times+=("$mod_time")
      fi
    done < <(find "$dir" -maxdepth 5 \( -name "venv" -o -name ".venv" -o -name "env" \) -type d -prune 2>/dev/null)
  done

  if [ ${#found[@]} -eq 0 ]; then
    echo "  ✅ No Python virtual environments found."
    return 0
  fi

  # Sort by size (largest first)
  local indices=()
  for i in "${!found[@]}"; do
    indices+=("$i")
  done

  IFS=$'\n' sorted_indices=($(for i in "${indices[@]}"; do echo "$i ${sizes[$i]}"; done | sort -k2 -rn | awk '{print $1}'))
  unset IFS

  echo ""
  printf "  %-4s %-12s %-20s %s\n" "#" "Size" "Last Modified" "Path"
  echo "  ──── ──────────── ──────────────────── ──────────────────────────────"

  local count=1
  local display_map=()
  for idx in "${sorted_indices[@]}"; do
    display_map+=("$idx")
    printf "  %-4s %-12s %-20s %s\n" "$count)" "$(human_readable "${sizes[$idx]}")" "${times[$idx]}" "${found[$idx]}"
    count=$(( count + 1 ))
  done

  echo ""
  local selection
  read -p "  Enter numbers to delete (comma-separated), 'a' for all, or 'n' to skip: " selection

  if [ "$selection" = "n" ] || [ -z "$selection" ]; then
    echo "  ⏭️  Skipped."
    return 0
  fi

  local to_delete=()
  local delete_size_kb=0

  if [ "$selection" = "a" ]; then
    for idx in "${display_map[@]}"; do
      to_delete+=("${found[$idx]}")
      delete_size_kb=$(( delete_size_kb + sizes[$idx] ))
    done
  else
    IFS=',' read -ra nums <<< "$selection"
    for num in "${nums[@]}"; do
      num=$(echo "$num" | tr -d ' ')
      if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#display_map[@]} ]; then
        local real_idx="${display_map[$(( num - 1 ))]}"
        to_delete+=("${found[$real_idx]}")
        delete_size_kb=$(( delete_size_kb + sizes[$real_idx] ))
      else
        echo "  ⚠️  Invalid selection: $num"
      fi
    done
  fi

  if [ ${#to_delete[@]} -eq 0 ]; then
    echo "  ⏭️  Nothing selected."
    return 0
  fi

  echo ""
  echo "  Will delete ${#to_delete[@]} virtual environments ($(human_readable "$delete_size_kb"))."

  if confirm_destructive "  🗑️  Delete selected virtual environments?"; then
    for dir in "${to_delete[@]}"; do
      echo "    🗑️  Deleting $dir..."
      safe_rm "$dir"
    done
    TOTAL_FREED_KB=$(( TOTAL_FREED_KB + delete_size_kb ))
    echo "  ✅ Python venv cleanup complete."
  else
    echo "  ⏭️  Cancelled."
  fi
}

scan_go_cache() {
  echo ""
  echo "  🔍 Scanning Go caches..."

  local go_mod_cache="$REAL_HOME/go/pkg/mod"
  local go_build_cache="$REAL_HOME/Library/Caches/go-build"
  local total_kb=0

  if [ -d "$go_mod_cache" ]; then
    local mod_kb
    mod_kb=$(get_dir_size_kb "$go_mod_cache")
    total_kb=$(( total_kb + mod_kb ))
    echo "    $(human_readable "$mod_kb")  $go_mod_cache (module cache)"
  fi

  if [ -d "$go_build_cache" ]; then
    local build_kb
    build_kb=$(get_dir_size_kb "$go_build_cache")
    total_kb=$(( total_kb + build_kb ))
    echo "    $(human_readable "$build_kb")  $go_build_cache (build cache)"
  fi

  if [ "$total_kb" -eq 0 ]; then
    echo "  ✅ No Go caches found."
    return 0
  fi

  echo ""
  echo "  Total: $(human_readable "$total_kb")"

  if confirm "  🗑️  Clean Go caches?"; then
    if command -v go &>/dev/null; then
      if [ -d "$go_mod_cache" ]; then
        if [ "$DRY_RUN" = true ]; then
          echo "    [DRY RUN] Would run: go clean -modcache"
        else
          go clean -modcache 2>/dev/null || safe_rm "$go_mod_cache"
        fi
      fi
      if [ -d "$go_build_cache" ]; then
        if [ "$DRY_RUN" = true ]; then
          echo "    [DRY RUN] Would run: go clean -cache"
        else
          go clean -cache 2>/dev/null || safe_rm "$go_build_cache"
        fi
      fi
    else
      [ -d "$go_mod_cache" ] && safe_rm "$go_mod_cache"
      [ -d "$go_build_cache" ] && safe_rm "$go_build_cache"
    fi
    TOTAL_FREED_KB=$(( TOTAL_FREED_KB + total_kb ))
    echo "  ✅ Go caches cleaned."
  else
    echo "  ⏭️  Skipped."
  fi
}

clean_package_caches() {
  echo ""
  echo "  🔍 Scanning package manager caches..."

  local npm_cache="$REAL_HOME/.npm/_cacache"
  local pnpm_store="$REAL_HOME/Library/pnpm/store"
  local yarn_cache="$REAL_HOME/Library/Caches/Yarn"
  local pip_cache="$REAL_HOME/Library/Caches/pip"
  local brew_cache="$REAL_HOME/Library/Caches/Homebrew"
  local cargo_cache="$REAL_HOME/.cargo/registry"

  local total_kb=0
  for c in "$npm_cache" "$pnpm_store" "$yarn_cache" "$pip_cache" "$brew_cache" "$cargo_cache"; do
    if [ -d "$c" ]; then
      local size_kb
      size_kb=$(get_dir_size_kb "$c")
      total_kb=$(( total_kb + size_kb ))
      echo "    $(human_readable "$size_kb")  $c"
    fi
  done

  if [ "$total_kb" -eq 0 ]; then
    echo "  ✅ No package manager caches found."
    return 0
  fi

  echo ""
  echo "  Total: $(human_readable "$total_kb")"
  echo "  Note: these use each tool's own GC where available, so only"
  echo "        unreferenced content is dropped. Everything is re-fetchable."

  if confirm "  🗑️  Clean package manager caches?"; then
    if [ "$DRY_RUN" = true ]; then
      echo "    [DRY RUN] Would run: npm cache verify / pnpm store prune / yarn cache clean"
      echo "    [DRY RUN] Would run: pip cache purge / brew cleanup --prune=all / cargo-cache"
    else
      # `npm cache verify` solo compacta el indice: medido el 2026-09-08,
      # dejo ~/.npm en 5.1 GB. `clean --force` lo bajo a 201 MB. Todo el
      # contenido se vuelve a descargar solo, asi que se usa el que libera.
      command -v npm   &>/dev/null && npm cache clean --force >/dev/null 2>&1 || true
      command -v pnpm  &>/dev/null && pnpm store prune >/dev/null 2>&1 || true
      command -v yarn  &>/dev/null && yarn cache clean >/dev/null 2>&1 || true
      command -v pip3  &>/dev/null && pip3 cache purge >/dev/null 2>&1 || true
      command -v brew  &>/dev/null && brew cleanup --prune=all >/dev/null 2>&1 || true
      # cargo: estaba en la LISTA de tamaños pero no se limpiaba nunca.
      # `cache/` y `src/` son descargas; `index/` es el indice del registro
      # (1.1 GB medido) y tarda en reconstruirse — se deja salvo --yes.
      safe_rm "$REAL_HOME/.cargo/registry/cache" "$REAL_HOME/.cargo/registry/src"
      command -v go &>/dev/null && go clean -cache >/dev/null 2>&1 || true
      safe_rm_contents "$brew_cache"
    fi
    TOTAL_FREED_KB=$(( TOTAL_FREED_KB + total_kb ))
    echo "  ✅ Package manager caches cleaned."
  else
    echo "  ⏭️  Skipped."
  fi
}

clean_docker() {
  echo ""
  echo "  🔍 Scanning Docker..."

  if ! command -v docker &>/dev/null; then
    echo "  ✅ Docker not installed."
    return 0
  fi

  if ! docker info &>/dev/null; then
    echo "  ⚠️  Docker is not running — start Docker Desktop to reclaim this space."
    return 0
  fi

  docker system df 2>/dev/null | sed 's/^/    /'

  # El numero que importa en macOS no sale en `docker system df`: es el
  # fichero de disco de la VM. Medido el 2026-09-08: 40 GB reservados con
  # 23 GB reales, el mayor consumidor de todo el disco con diferencia.
  local raw="$REAL_HOME/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
  if [ -f "$raw" ]; then
    echo ""
    echo "    $(human_readable "$(get_dir_size_kb "$raw")")  Docker.raw (real size on disk)"
  fi

  echo ""
  echo "  This prunes the build cache and images not used by any container."
  echo "  Named volumes are left alone (they may hold database data)."

  if confirm "  🗑️  Prune Docker build cache and unused images?"; then
    if [ "$DRY_RUN" = true ]; then
      echo "    [DRY RUN] Would run: docker builder prune -af && docker image prune -af"
    else
      docker builder prune -af 2>/dev/null | tail -1 | sed 's/^/    /'
      docker image prune -af 2>/dev/null | tail -1 | sed 's/^/    /'
      echo ""
      echo "    ⚠️  Pruning frees space INSIDE the VM, not on your disk yet."
      echo "        Docker.raw only shrinks when Docker Desktop restarts and"
      echo "        trims the image. Do that now if you are short on space:"
      echo "          osascript -e 'quit app \"Docker\"' && open -a Docker"
    fi
    echo "  ✅ Docker pruned."
  else
    echo "  ⏭️  Skipped."
  fi
}

clean_browser_binaries() {
  echo ""
  echo "  🔍 Scanning headless browser downloads..."

  local roots=(
    "$REAL_HOME/.cache/puppeteer/chrome"
    "$REAL_HOME/.cache/puppeteer/chrome-headless-shell"
    "$REAL_HOME/Library/Caches/ms-playwright"
  )

  local stale=()
  local total_kb=0

  for root in "${roots[@]}"; do
    [ -d "$root" ] || continue

    # Entries look like "<product>-<build>" (chromium-1187, ffmpeg-1011,
    # mac_arm-142.0.7444.162). Group by product and keep the newest build
    # of each — sorting the whole directory together would delete browsers
    # that are still in use just because another product has a higher build.
    local products=()
    while IFS= read -r prod; do
      [ -n "$prod" ] && products+=("$prod")
    done < <(ls -1 "$root" 2>/dev/null | sed -n 's/^\(.*\)-[^-]*$/\1/p' | sort -u)

    for prod in "${products[@]}"; do
      local revs=()
      while IFS= read -r r; do
        [ -n "$r" ] && revs+=("$r")
      done < <(ls -1 "$root" 2>/dev/null | grep -E "^${prod}-[^-]+$" | sort -V)

      local n=${#revs[@]}
      [ "$n" -le 1 ] && continue

      local i=0
      while [ "$i" -lt $(( n - 1 )) ]; do
        local path="$root/${revs[$i]}"
        local size_kb
        size_kb=$(get_dir_size_kb "$path")
        stale+=("$path")
        total_kb=$(( total_kb + size_kb ))
        echo "    $(human_readable "$size_kb")  $path"
        i=$(( i + 1 ))
      done
      echo "    (keeping newest $prod: ${revs[$(( n - 1 ))]})"
    done
  done

  if [ ${#stale[@]} -eq 0 ]; then
    echo "  ✅ No stale browser revisions found."
    return 0
  fi

  echo ""
  echo "  Total: $(human_readable "$total_kb")"

  if confirm "  🗑️  Delete stale browser revisions?"; then
    safe_rm "${stale[@]}"
    TOTAL_FREED_KB=$(( TOTAL_FREED_KB + total_kb ))
    echo "  ✅ Stale browser revisions removed."
  else
    echo "  ⏭️  Skipped."
  fi
}

clean_updater_caches() {
  echo ""
  echo "  🔍 Scanning app updater caches..."

  # Instaladores ya aplicados que las apps de Electron dejan en Caches y no
  # borran nunca. Medido el 2026-09-08 en esta maquina: 2.0 GB entre VS Code,
  # Notion y su updater. No los toca `clean_user_caches` porque ahi se decide
  # por directorio entero y estos viven mezclados con caches que si duelen.
  local targets=()
  local d
  for d in "$REAL_HOME/Library/Caches"/*.ShipIt \
           "$REAL_HOME/Library/Caches"/*-updater \
           "$REAL_HOME/Library/Caches/com.apple.python" \
           "$REAL_HOME/Library/Caches/Homebrew"; do
    [ -d "$d" ] && targets+=("$d")
  done

  local total_kb=0
  for d in "${targets[@]:-}"; do
    [ -n "$d" ] || continue
    local size_kb
    size_kb=$(get_dir_size_kb "$d")
    total_kb=$(( total_kb + size_kb ))
    echo "    $(human_readable "$size_kb")  $d"
  done

  if [ "$total_kb" -eq 0 ]; then
    echo "  ✅ No updater caches found."
    return 0
  fi

  echo ""
  echo "  Total: $(human_readable "$total_kb")"
  echo "  These are downloaded installers for updates already applied."

  if confirm "  🗑️  Delete updater caches?"; then
    safe_rm_contents "${targets[@]}"
    TOTAL_FREED_KB=$(( TOTAL_FREED_KB + total_kb ))
    echo "  ✅ Updater caches cleaned."
  else
    echo "  ⏭️  Skipped."
  fi
}

clean_xdg_caches() {
  echo ""
  echo "  🔍 Scanning ~/.cache (tool caches)..."

  # El script solo miraba ~/Library/Caches, que es la convencion de macOS.
  # Pero las herramientas de linea de comandos (uv, prisma, puppeteer, mole,
  # node-gyp...) escriben en ~/.cache, y ahi habia 1.7 GB sin vigilar.
  #
  # Que NO se toca, y por que:
  #   nvim / gitstatus  reinstalar lazy.nvim y treesitter es lento y a veces
  #                     interactivo — no es "se regenera solo".
  #   opencode          cache del binario que estas usando.
  #   puppeteer         es un binario de Chrome de ~500 MB, y ademas la
  #                     opcion 10 YA lo gestiona bien: borra las revisiones
  #                     viejas y conserva la mas nueva. Vaciarlo entero aqui
  #                     deshace ese cuidado y obliga a re-descargar.
  local skip="nvim opencode gitstatus puppeteer ms-playwright"
  local targets=()
  local d name size_kb
  local total_kb=0

  # Solo entra en `targets` lo que se ha ENSEÑADO. Antes la lista se filtraba
  # a >1 MB para imprimir pero se borraba entera: se cargaba directorios que
  # el usuario no llego a ver.
  for d in "$REAL_HOME/.cache"/*; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    case " $skip " in *" $name "*) continue ;; esac
    size_kb=$(get_dir_size_kb "$d")
    [ "$size_kb" -lt 1024 ] && continue
    targets+=("$d")
    total_kb=$(( total_kb + size_kb ))
    echo "    $(human_readable "$size_kb")  $d"
  done

  if [ "$total_kb" -eq 0 ]; then
    echo "  ✅ Nothing worth cleaning in ~/.cache."
    return 0
  fi

  echo ""
  echo "  Total: $(human_readable "$total_kb")   (untouched: $skip)"

  if confirm "  🗑️  Empty these tool caches?"; then
    safe_rm_contents "${targets[@]}"
    TOTAL_FREED_KB=$(( TOTAL_FREED_KB + total_kb ))
    echo "  ✅ Tool caches cleaned."
  else
    echo "  ⏭️  Skipped."
  fi
}

report_top_consumers() {
  echo ""
  echo "  🔍 Top space consumers (read-only, deletes nothing)..."
  echo ""

  local roots=(
    "$REAL_HOME/Library/Containers"
    "$REAL_HOME/Library/Application Support"
    "$REAL_HOME/Library/Group Containers"
    "$REAL_HOME/Library/Caches"
    "$REAL_HOME/.cache"
    "$REAL_HOME/Downloads"
    "$REAL_HOME/Documents"
  )

  local r
  for r in "${roots[@]}"; do
    [ -d "$r" ] || continue
    echo "  $r"
    du -sk "$r"/* 2>/dev/null | sort -rn | head -5 | while read -r kb path; do
      echo "    $(human_readable "$kb")  $(basename "$path")"
    done
    echo ""
  done

  echo "  Free space now: $(human_readable "$(get_free_space_kb)")"
  echo ""
  echo "  Reminder: what this report cannot decide for you —"
  echo "    node_modules (option 5), Downloads, and anything under Documents."
}

# ============================================
#   Menu and Main
# ============================================

show_menu() {
  echo ""
  echo "  ============================================"
  echo "    🧹 macOS System Cleaner"
  if [ "$DRY_RUN" = true ]; then
    echo "    ⚠️  DRY RUN MODE — nothing will be deleted"
  fi
  echo "  ============================================"
  echo ""
  echo "  Cache Cleaning:"
  echo "    1)  User caches         (~/Library/Caches, CrashReporter, Logs)"
  echo "    2)  System caches       (/Library/Caches)       [requires sudo]"
  echo "    3)  Temporary files     (/private/tmp)          [requires sudo]"
  echo ""
  echo "  System:"
  echo "    4)  Flush DNS cache                             [requires sudo]"
  echo ""
  echo "  Developer Cleanup:"
  echo "    5)  Scan node_modules   (find stale node_modules and selectively delete)"
  echo "    6)  Scan Python venvs   (find .venv/venv/env and selectively delete)"
  echo "    7)  Scan Go module cache (~/go/pkg/mod and build cache)"
  echo "    8)  Package manager caches (npm, pnpm, yarn, pip, brew, cargo)"
  echo "    9)  Docker            (build cache + unused images)"
  echo "    10) Headless browsers (stale puppeteer/playwright revisions)"
  echo "    11) App updater caches (*.ShipIt, *-updater — installers already applied)"
  echo "    12) Tool caches       (~/.cache: uv, prisma, puppeteer... keeps nvim)"
  echo ""
  echo "  Report:"
  echo "    r)  Top space consumers (read-only, deletes nothing)"
  echo ""
  echo "  Batch:"
  echo "    a)  All cache cleaning (1-4)"
  echo "    d)  All developer cleanup (5-12)"
  echo "    s)  Safe sweep, no questions asked (8,9,11,12 — pure re-fetchable cache)"
  echo "    0)  Everything (1-12)"
  echo ""
  echo "    q)  Quit"
  echo ""
}

run_option() {
  case "$1" in
    1) clean_user_caches ;;
    2) clean_system_caches ;;
    3) clean_temp_files ;;
    4) flush_dns ;;
    5) scan_node_modules ;;
    6) scan_python_venvs ;;
    7) scan_go_cache ;;
    8) clean_package_caches ;;
    9) clean_docker ;;
    10) clean_browser_binaries ;;
    11) clean_updater_caches ;;
    12) clean_xdg_caches ;;
    r) report_top_consumers ;;
    *) echo "  ⚠️  Invalid option: $1" ;;
  esac
}

show_summary() {
  local final_kb
  final_kb=$(get_free_space_kb)
  local actual_kb=$(( final_kb - INITIAL_FREE_KB ))
  [ "$actual_kb" -lt 0 ] && actual_kb=0
  local freed_display
  freed_display=$(human_readable "$TOTAL_FREED_KB")
  local final_display
  final_display=$(human_readable "$final_kb")

  echo ""
  echo "  ============================================"
  echo "    📊 Cleaning Summary"
  echo "  ============================================"
  echo "  Free space now:    $final_display"
  echo "  Estimated freed:   $freed_display"
  if [ "$DRY_RUN" != true ]; then
    echo "  Actually freed:    $(human_readable "$actual_kb")"
  fi
  if [ "$DRY_RUN" = true ]; then
    echo "  ⚠️  DRY RUN — nothing was actually deleted"
  fi
  echo "  ============================================"
  echo ""
  echo "  🎉 Done!"
  echo ""
}

main() {
  local selection
  if [ -n "$ONLY" ]; then
    # Sin menu y sin `read`: es la unica forma de que esto se pueda lanzar
    # desde un agente, un alias o cron. Sin --only el script se BLOQUEA en el
    # primer prompt y parece colgado.
    selection="$ONLY"
    echo ""
    echo "  🧹 macOS System Cleaner — running: $selection"
    [ "$DRY_RUN" = true ] && echo "  ⚠️  DRY RUN — nothing will be deleted"
    [ "$AUTO_YES" = true ] && echo "  ⚠️  --yes — every confirmation auto-accepted"
  else
    show_menu
    read -p "  Select options (comma-separated, e.g. 1,3,5): " selection
  fi

  if [ "$selection" = "q" ] || [ -z "$selection" ]; then
    echo "  Goodbye!"
    exit 0
  fi

  local options=()

  case "$selection" in
    a) options=(1 2 3 4) ;;
    d) options=(5 6 7 8 9 10 11 12) ;;
    s) options=(8 9 11 12); AUTO_YES=true ;;
    0) options=(1 2 3 4 5 6 7 8 9 10 11 12) ;;
    *)
      IFS=',' read -ra options <<< "$selection"
      ;;
  esac

  INITIAL_FREE_KB=$(get_free_space_kb)

  for opt in "${options[@]}"; do
    opt=$(echo "$opt" | tr -d ' ')
    run_option "$opt"
  done

  show_summary
}

main
