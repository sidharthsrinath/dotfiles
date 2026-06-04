#!/usr/bin/env bash

# ── helpers ──────────────────────────────────────────────────────────────────

info()    { echo "[info]  $*"; }
success() { echo "[ok]    $*"; }
prompt()  { read -rp "[?]     $* [y/N] " ans; [[ "$(echo "$ans" | tr '[:upper:]' '[:lower:]')" == "y" ]]; }

brew_install() {
  local pkg="${*: -1}"  # package name is always the last arg (handles --cask flag)
  if brew list --formula "$pkg" &>/dev/null || brew list --cask "$pkg" &>/dev/null; then
    info "$pkg already installed, skipping"
  else
    info "Installing $pkg..."
    brew install "$@"
    success "$pkg installed"
  fi
}

# Creates a symlink, backing up the target if it already exists and isn't
# already the right symlink.
safe_link() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    info "$(basename "$dest") already linked"
    return
  fi
  if [[ -e "$dest" ]]; then
    mv "$dest" "$dest.bak"
    info "Backed up existing $(basename "$dest") to $(basename "$dest").bak"
  fi
  ln -sf "$src" "$dest"
  success "Linked $(basename "$dest")"
}

# Appends a source line to a shell rc file if it isn't there yet.
append_source() {
  local rc="$1" src_path="$2"
  touch "$rc"
  if grep -qF "$src_path" "$rc"; then
    info "$(basename "$rc") already sources $src_path"
  else
    echo "" >> "$rc"
    echo "source $src_path" >> "$rc"
    success "Added 'source $src_path' to $(basename "$rc")"
  fi
}

# ── allow sourcing for tests ──────────────────────────────────────────────────
[[ -n "${DOTFILES_TEST_SOURCING:-}" ]] && return 0

# ── main (only runs when executed directly) ───────────────────────────────────
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"

# ── homebrew ─────────────────────────────────────────────────────────────────

if ! command -v brew &>/dev/null; then
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
  success "Homebrew installed"
else
  info "Homebrew already installed"
fi

# ── core tools ───────────────────────────────────────────────────────────────

info "Installing core tools..."
brew tap koekeishiya/formulae
brew_install tmux
brew_install neovim
brew_install git-lfs
brew_install gitmux
brew_install skhd
brew_install --cask ghostty

# nb (notes CLI) — install from local script, not brew
if ! command -v nb &>/dev/null; then
  info "Installing nb (notes CLI)..."
  bash "$DOTFILES/nb/nb.sh" update
fi

# ── optional tools ───────────────────────────────────────────────────────────

if prompt "Install nvm (Node version manager)?"; then
  if [[ ! -d "$HOME/.nvm" ]]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
    success "nvm installed"
  else
    info "nvm already installed"
  fi
fi

if prompt "Install rbenv (Ruby version manager)?"; then
  brew_install rbenv ruby-build
fi

if prompt "Install pipx (Python tool installer)?"; then
  brew_install pipx
fi

if prompt "Install zig?"; then
  brew_install zig
fi

if prompt "Install git-delta (diff viewer)?"; then
  brew_install git-delta
fi

# ── work tools ───────────────────────────────────────────────────────────────

if prompt "Install sdkman (Java/JVM version manager — work)?"; then
  if [[ ! -d "$HOME/.sdkman" ]]; then
    curl -s "https://get.sdkman.io" | bash
    success "sdkman installed"
  else
    info "sdkman already installed"
  fi
fi

if prompt "Install ghcup (Haskell toolchain — work)?"; then
  if ! command -v ghcup &>/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
    success "ghcup installed"
  else
    info "ghcup already installed"
  fi
fi

# ── git-lfs init ─────────────────────────────────────────────────────────────

git lfs install --skip-repo
success "git-lfs initialized"

# ── symlinks for non-shell configs ───────────────────────────────────────────

info "Linking configs..."
safe_link "$DOTFILES/tmux/tmux.conf"   "$HOME/.tmux.conf"
safe_link "$DOTFILES/git/gitconfig"    "$HOME/.gitconfig"
safe_link "$DOTFILES/ghostty/config"   "$HOME/.config/ghostty/config"
safe_link "$DOTFILES/nvim"             "$HOME/.config/nvim"
safe_link "$DOTFILES/skhd/skhdrc"     "$HOME/.config/skhd/skhdrc"

# ── shell config: source (don't symlink) ─────────────────────────────────────

info "Wiring shell config..."
append_source "$HOME/.zshrc"    "$DOTFILES/shell/zshrc"
append_source "$HOME/.zprofile" "$DOTFILES/shell/zprofile"

# ── private-commands stub ────────────────────────────────────────────────────

if [[ ! -f "$DOTFILES/shell/private-commands.sh" ]]; then
  echo "# Private aliases and exports (gitignored)" > "$DOTFILES/shell/private-commands.sh"
  success "Created empty private-commands.sh"
fi

# ── done ─────────────────────────────────────────────────────────────────────

echo ""
echo "Done. Open a new shell or run: source ~/.zshrc"
echo ""
echo "Remaining manual steps:"
echo "  1. Create ~/.gitconfig.local with [user] name and email"
echo "  2. Run 'skhd --start-service' to start the hotkey daemon"
