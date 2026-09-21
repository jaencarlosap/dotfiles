# Dotfiles

## Quick start (new machine)

```bash
git clone <this repo> ~/Documents/personal/dotfiles && cd ~/Documents/personal/dotfiles
make setup          # interactive installer: tick what to install / authenticate / run, in order
```

`make setup` builds and opens `dtool` on its **Installer** page: a checklist with
opencode config, herdr, Neovim, `gh auth login`, one line per MCP server from the
catalog (showing whether it is already authenticated), and the disk cleanups.
`space` toggles, `p` selects only what is pending, `enter` runs the selection in
order — each step in the real terminal, so `sudo` and OAuth browser prompts work.
`make setup_dry` shows the commands without running them.


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

Non-interactive (what an agent or cron should run; freed 35 GB on 2026-09-19):
```bash
make clean_disk         # user caches, Go, npm/pnpm/yarn/pip/brew/cargo, Docker (no volumes), updaters, ~/.cache
make clean_disk_dry     # sizes only
make clean_disk_sudo    # system caches, /private/tmp, DNS (asks for sudo)
```
Interactive menu (blocks on a prompt — for a human at the keyboard):
```bash
make clean_system
```
The scripts live in `scripts/`; `dtool` is the TUI version of the same flows.
</details>

<details>
<summary>herdr (persistent runtime for the agents, tmux-style)</summary>

[herdr](https://herdr.dev) keeps the agents' terminals alive in a background
server: close the lid, drop the network, reconnect later from the Mac or from
the phone (any SSH client over Tailscale — there is no official mobile app; the
"Herdr Mobile" on Google Play is third-party). Config lives in `herdr-config/`
and is symlinked to `~/.config/herdr/config.toml`. Keybindings follow
neovim/LazyVim habits: see the comments in the file, or `prefix+?` inside herdr.

```bash
make install_herdr   # brew install herdr + symlink config + opencode/claude integrations + config check
make herdr_status    # client/server state, integrations, and the exact ssh line for the phone
make uninstall_herdr # remove the config symlink only
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