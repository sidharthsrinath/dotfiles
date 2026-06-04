# dotfiles

Configuration for shell, editor, terminal, and dev tools.

## Structure

```
dotfiles/
├── shell/          # zsh config (zshrc, zprofile, prompt, commands)
├── git/            # gitconfig and delta diff settings
├── tmux/           # tmux config and gitmux status bar
├── ghostty/        # Ghostty terminal config
├── nvim/           # Neovim config (lazy.nvim)
├── skhd/           # macOS hotkey daemon
└── nb/             # nb notes CLI wrapper
```

## Install

```bash
cd ~/dotfiles
./install.sh
```

The script will:
- Install Homebrew if missing
- Install core tools (tmux, neovim, ghostty, git-lfs, gitmux)
- Prompt before installing optional/work-specific tools
- Create symlinks for non-shell configs
- Append `source` lines to your existing `~/.zshrc` and `~/.zprofile` (safe — won't overwrite)

### Manual steps after install

1. **Git identity** — create `~/.gitconfig.local` (not tracked):
   ```ini
   [user]
       name = Your Name
       email = you@example.com
   ```

2. **Private shell commands** — create `~/dotfiles/shell/private-commands.sh` (gitignored):
   ```bash
   # Put aliases/exports that shouldn't be committed here
   ```

3. **skhd** — start the hotkey daemon:
   ```bash
   skhd --start-service
   ```

## Adding a new machine

For machines where some tools don't apply (e.g. no sdkman, no Haskell), the zshrc guards each tool with an existence check — tools that aren't installed are silently skipped.
