#!/usr/bin/env bash

set -e  # Stop on error
set -u  # Treat unset variables as errors

NVIM_CONFIG_REPO_DIR="$(pwd)/nvim"
LOCAL_NVIM_DIR="$HOME/.config/nvim"

echo "🔗 Linking Neovim config..."
rm -rf "$LOCAL_NVIM_DIR"
ln -s "$NVIM_CONFIG_REPO_DIR" "$LOCAL_NVIM_DIR"
echo "✅ Linked $LOCAL_NVIM_DIR → $NVIM_CONFIG_REPO_DIR"

echo "🍺 Installing dependencies with Homebrew..."
brew update
brew install neovim ripgrep fd lazygit fzf

echo "🧰 Installing packer.nvim (if needed)..."
PACKER_DIR="$HOME/.local/share/nvim/site/pack/packer/start/packer.nvim"
if [ ! -d "$PACKER_DIR" ]; then
    git clone --depth 1 https://github.com/wbthomason/packer.nvim "$PACKER_DIR"
    echo "✅ packer.nvim installed"
else
    echo "✔️ packer.nvim already exists"
fi

echo "🚀 Opening Neovim to install plugins..."
nvim --headless "+Lazy! sync" +qa

echo "🎉 Setup complete!"
