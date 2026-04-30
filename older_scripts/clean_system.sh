#!/bin/bash
set -e
set -u

# ============================================
#   macOS System Cleaner v2.0
# ============================================

# ---- Global State ----
DRY_RUN=false
TOTAL_FREED_KB=0
IS_ROOT=false

# ---- Parse Arguments ----
show_help() {
  echo "Usage: clean_system.sh [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --dry-run   Show what would be deleted without actually deleting"
  echo "  --help, -h  Show this help message"
  echo ""
  echo "Run without sudo for user-level and developer cleanup."
  echo "Run with sudo for system-level operations (system caches, DNS flush, temp files)."
}

for arg in "${@:-}"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
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
  local kb=$1
  if [ "$kb" -ge 1048576 ]; then
    echo "$(awk "BEGIN {printf \"%.2f\", $kb / 1048576}") GB"
  elif [ "$kb" -ge 1024 ]; then
    echo "$(awk "BEGIN {printf \"%.1f\", $kb / 1024}") MB"
  else
    echo "${kb} KB"
  fi
}

safe_rm() {
  local target="$1"
  if [ "$DRY_RUN" = true ]; then
    echo "    [DRY RUN] Would delete: $target"
  else
    rm -rf "$target" 2>/dev/null || true
  fi
}

confirm() {
  local prompt="$1"
  local response
  read -p "$prompt (y/N): " response
  [[ "$response" =~ ^[Yy]$ ]]
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
          safe_rm "$expanded"/*
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
    safe_rm "$target"/*
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
    safe_rm "$target"/*
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
  echo ""
  echo "  Batch:"
  echo "    a)  All cache cleaning (1-4)"
  echo "    d)  All developer cleanup (5-7)"
  echo "    0)  Everything (1-7)"
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
    *) echo "  ⚠️  Invalid option: $1" ;;
  esac
}

show_summary() {
  local final_kb
  final_kb=$(get_free_space_kb)
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
  if [ "$DRY_RUN" = true ]; then
    echo "  ⚠️  DRY RUN — nothing was actually deleted"
  fi
  echo "  ============================================"
  echo ""
  echo "  🎉 Done!"
  echo ""
}

main() {
  show_menu

  local selection
  read -p "  Select options (comma-separated, e.g. 1,3,5): " selection

  if [ "$selection" = "q" ] || [ -z "$selection" ]; then
    echo "  Goodbye!"
    exit 0
  fi

  local options=()

  case "$selection" in
    a) options=(1 2 3 4) ;;
    d) options=(5 6 7) ;;
    0) options=(1 2 3 4 5 6 7) ;;
    *)
      IFS=',' read -ra options <<< "$selection"
      ;;
  esac

  local initial_kb
  initial_kb=$(get_free_space_kb)

  for opt in "${options[@]}"; do
    opt=$(echo "$opt" | tr -d ' ')
    run_option "$opt"
  done

  show_summary
}

main
