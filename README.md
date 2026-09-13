# Dotfiles

Repository to unify the commands that I use most daily


<details>
<summary>Neovim Config</summary>

# 💤 LazyVim configuration

This repository has the configuration from [LazyVim](https://github.com/LazyVim/LazyVim).

## Install

```bash
make install_nvim          # asks before installing Homebrew
make install_nvim YES=1    # non-interactive
```

Idempotent — re-run it any time; every step checks first and skips what is
already there:

1. Xcode Command Line Tools (git + C compiler for treesitter)
2. Homebrew, installed with the official script if missing
3. Neovim — `brew install neovim` on a native `/opt/homebrew`; on an Apple
   Silicon Mac whose Homebrew lives in `/usr/local` (Intel/Rosetta install,
   no bottles anymore, neovim's deps fail to compile) the official arm64
   release goes into `~/.local/nvim` with `~/.local/bin/nvim` linked to it.
   The check *runs* `nvim` rather than asking brew, so a brew build broken by
   a library upgrade is detected and replaced.
   Then `ripgrep fd lazygit fzf node` (only the missing ones) and the
   tree-sitter CLI via `npm` (same bottle problem: brew's `tree-sitter-cli`
   builds rust from source there)
4. Hack Nerd Font
5. `~/.config/nvim` → `nvim-config/` (an existing real config is moved to
   `~/.config/nvim.bak-<date>`, never deleted)
6. lazy.nvim + plugins at the versions pinned in `lazy-lock.json`
   (`:Lazy restore`, not `sync`, so a fresh machine gets the same versions)
7. A `:checkhealth lazy lazyvim` summary

The first interactive `nvim` then installs treesitter parsers and LSP servers
on its own. Select **Hack Nerd Font** in your terminal profile for the icons.

> [!NOTE]
> The same flow exists in `dtool` → *Neovim Setup*, except that Homebrew
> itself is only installed by the `make` target (its installer is interactive).

> [!NOTE]
> If it generate some error related to load the lazy plugins try remove the local shares `rm -rf ~/.local/share/nvim/`

</details>

<details>
<summary>Clean Macos System</summary>

To clean your system files and cache, you can run
```bash
make clean_system
```
</details>

<details>
<summary>opencode Config (local models on pcgamer)</summary>

Versioned [opencode](https://opencode.ai) config pointing to a local LM Studio
server (`pcgamer`, via Tailscale, 12GB VRAM). Lives in `opencode-config/`, which
is the source of truth; installing symlinks `~/.config/opencode` to it.

```bash
make install_opencode     # symlink ~/.config/opencode -> opencode-config/ (backs up first)
make opencode_status      # show symlink state
make uninstall_opencode   # remove the symlinks
```

More detail (per-model routing, and the LM Studio load settings that fix the
slowness) in [`opencode-config/README.md`](opencode-config/README.md).
</details>