# Dotfiles

Repository to unify the commands that I use most daily


<details>
<summary>Neovim Config</summary>

# 💤 LazyVim configuration

This repository has the configuration from [LazyVim](https://github.com/LazyVim/LazyVim).

## To start using this configuration follow these steps:

To install the current confing you can run 

```bash
make install_nvim
```

Install dependencies

```bash
  brew install neovim
  brew install lazygit
  brew install ripgrep
  brew install fd
  brew tap homebrew/cask-fonts
  brew install --cask font-hack-nerd-font
```
> [!NOTE]
> If it generates some error related to the developer tools try this command: `xcode-select --install`

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