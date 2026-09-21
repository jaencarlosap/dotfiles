# scripts

Shell scripts the root `makefile` runs. They are the non-interactive,
scriptable path (make, cron, an agent); `../dtool/` is the Go TUI with the
same flows for a human at the keyboard. Both stay: they serve different callers.

| Script            | make target(s)                                   | dtool page     |
|-------------------|--------------------------------------------------|----------------|
| `clean_system.sh` | `clean_disk`, `clean_disk_dry`, `clean_disk_sudo`, `clean_system` (menu) | System Cleaner |
| `setup_nvim.sh`   | `install_nvim`                                   | Neovim Setup   |
| `burn-iso.sh`     | —                                                | ISO Burner     |
| `dotfiles.sh`     | —                                                | Git Tools      |

`clean_system.sh` gotchas:

- Without `--only` it shows a menu and **blocks** on `read`. From make/cron/an
  agent always pass `--only user|sudo|<numbers>` and usually `--yes`.
- `--only user` = 1,7,8,9,10,11,12: everything that needs no sudo and asks no
  per-item question. Options 5 and 6 (node_modules, venvs) always ask which
  ones to delete, so they are never in a preset.
- Docker: prunes build cache and unused images, never named volumes.
  `Docker.raw` (the VM disk) only shrinks after Docker Desktop restarts.
- `--dry-run` shows sizes; the "estimated" total is an upper bound (tools with
  their own GC free less).

History: these were moved from the repo root to `older_scripts/` during the
dtool migration (see `../plan-migration.md`) and renamed to `scripts/` on
2026-09-19 once it was clear they are the ones actually in use.
