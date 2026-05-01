###
### Custom commands, mainly to simplify filesystem and terminal operations
###

## Filesystem navigation

# Make a new directory and navigate to it
mkcd() { mkdir "$1" && cd "$1"; }

## Terminal session commands

# Clear terminal screen and restart session
restart() {{ clear && source ~/.zshrc && echo "Reloaded zsh config and started new session" }}

# Navigate to documents folder
docs() { cd ~/Documents }

# Navigate to dotfiles folder
dotfiles() { cd ~/dotfiles }

# Private custom commands
source ~/dotfiles/private-commands.sh


### Confirmation
echo "Loaded custom commands"