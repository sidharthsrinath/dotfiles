### 
### Opened by non-login shell, set up interactive commands 
### 

# Load the prompt config
source ~/dotfiles/vcs_info_prompt.zsh >/dev/null

# Custom commands
source ~/dotfiles/commands.sh >/dev/null

# Load `.claude`
export CLAUDE_CONFIG_DIR="$HOME/dotfiles/.claude"

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# SDKMAN - THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
export PATH="$HOME/dotfiles/tmux:$PATH"
export PATH="/opt/homebrew/opt/zig@0.15/bin:$PATH"
eval "$(rbenv init - zsh)"


[ -f "/Users/sidharth/.ghcup/env" ] && . "/Users/sidharth/.ghcup/env" # ghcup-env
# Created by `pipx` on 2026-05-27 23:32:17
export PATH="$PATH:/Users/sidharth/.local/bin"
