#!/bin/bash

set -e

HOSTNAME=$(hostname)
SCAN_DIR=~/dev_env_scan_$HOSTNAME
mkdir -p "$SCAN_DIR"

echo "🔍 Scanning environment on $HOSTNAME..."

echo "🖥️ System Info" > "$SCAN_DIR/system_info.txt"
uname -a >> "$SCAN_DIR/system_info.txt"
sw_vers >> "$SCAN_DIR/system_info.txt"
sysctl -n machdep.cpu.brand_string >> "$SCAN_DIR/system_info.txt"
arch >> "$SCAN_DIR/system_info.txt"

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >/dev/null 2>&1 || true

echo "🍺 Homebrew Info"
which brew > "$SCAN_DIR/brew_path.txt" 2>/dev/null || echo "Homebrew not found"
brew config > "$SCAN_DIR/brew_config.txt" 2>/dev/null || true
brew list --versions > "$SCAN_DIR/brew_list_versions.txt" 2>/dev/null || true
brew list --pinned > "$SCAN_DIR/brew_pinned.txt" 2>/dev/null || true
brew outdated > "$SCAN_DIR/brew_outdated.txt" 2>/dev/null || true
brew bundle dump --file="$SCAN_DIR/Brewfile" --force > /dev/null 2>&1 || true

echo "🔐 MDM Profiles"
sudo profiles list > "$SCAN_DIR/mdm_profiles.txt" 2>/dev/null || echo "No profiles or permission denied"

echo "🐍 Python Packages"
pip3 freeze > "$SCAN_DIR/requirements.txt" 2>/dev/null || echo "No Python packages"

echo "📦 Node Global Packages"
npm list -g --depth=0 > "$SCAN_DIR/npm_global.txt" 2>/dev/null || echo "No global npm packages"

echo "📜 Checking Dotfiles"
for file in .zshrc .bashrc .bash_profile .gitconfig .inputrc .npmrc; do
  [ -f ~/$file ] && cp ~/$file "$SCAN_DIR/"
done

echo "🧾 Listing custom script directories"
[ -d ~/scripts ] && cp -R ~/scripts "$SCAN_DIR/scripts"
[ -d ~/bin ] && cp -R ~/bin "$SCAN_DIR/bin"

echo "🗜️ Creating archive..."
tar -czf ~/dev_env_scan_$HOSTNAME.tar.gz -C "$SCAN_DIR" .

echo "✅ Done. Archive ready: ~/dev_env_scan_$HOSTNAME.tar.gz"

