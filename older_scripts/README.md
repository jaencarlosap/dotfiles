# older_scripts

Original shell scripts. Kept here as a fallback until `dtool` (the Go TUI in
`../dtool/`) is verified on this machine. Safe to delete once you're happy
with the Go port.

The contents of these files are **not** modified by the migration — they are
moved verbatim from the repo root via `git mv`, so `git log --follow` still
works. The root `makefile` keeps its old targets (`make clean_system`, etc.)
working by pointing at this directory.

| Script             | Replacement in dtool                  |
|--------------------|---------------------------------------|
| `clean_system.sh`  | `dtool` → System Cleaner              |
| `setup_nvim.sh`    | `dtool` → Neovim Setup                |
| `burn-iso.sh`      | `dtool` → ISO Burner                  |
| `dotfiles.sh`      | `dtool` → Git Tools                   |

When you're confident the Go port works for each flow, delete this whole
directory.
