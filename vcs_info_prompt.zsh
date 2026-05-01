### 
### Information about the version control system state displayed 
### in the command line prompt
### 

# --- Global Color Variables ---
# Use 'export' to ensure variables are available for PROMPT_SUBST evaluation.

# Base Colors
export CLR_TIME='%F{white}'      # Color for the current time
export CLR_PATH_DEFAULT='%F{blue}'   # Default color for the current path
export CLR_PATH_WORKTREE='%F{green}'  # Color for the path when in a Git worktree
export CLR_RESET='%f'                # Reset color to default (end of a color section)
export CLR_DEFAULT='%F{default}'     # Reset to default for zstyle formats

# Git Status Colors
export CLR_GIT_CLEAN='%F{white}'
export CLR_GIT_STAGED='%F{yellow}'
export CLR_GIT_UNSTAGED='%F{red}'
export CLR_GIT_UNPUSHED='%F{magenta}'
export CLR_GIT_UNTRACKED="${CLR_GIT_STAGED}" # Using the staged color for untracked files
export CLR_GIT_ACTION="${CLR_GIT_STAGED}"    # Using the staged color for ongoing actions

# Load the vcs_info module.
autoload -Uz vcs_info

# ----------------------------------------------------------------------------

# --- Git Styling and Configuration (Using Variables) ---
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr '↑'
zstyle ':vcs_info:git:*' unstagedstr '↓'

# Define the format for the prompt when in a Git repository.
# Note the use of double quotes for variable expansion.
zstyle ':vcs_info:git:*' formats "${CLR_DEFAULT}[%b]${CLR_RESET}"
# Define the format for when a Git action is in progress.
zstyle ':vcs_info:git:*' actionformats "${CLR_DEFAULT}[%b]${CLR_RESET}:${CLR_GIT_ACTION}%a${CLR_RESET}"

# ----------------------------------------------------------------------------

# --- Custom Hook Functions (Using Variables) ---

# This function checks for untracked files and adds a '?' to the prompt.
+vi-git-untracked() {
  if git rev-parse --is-inside-work-tree &> /dev/null &&
     git status --porcelain | grep '??' &> /dev/null ; then
    # Use the untracked color variable.
    hook_com[misc]+="${CLR_GIT_UNTRACKED} ? ${CLR_RESET}"
  fi
}

# This function changes the branch name color based on the Git status.
+vi-git-color-branch() {
  local staged unstaged color unpushed
  if git rev-parse --is-inside-work-tree &> /dev/null; then
    staged=$(git diff --cached --quiet || echo true)
    unstaged=$(git diff --quiet || echo true)
    unpushed=$(git rev-list --count @{u}.. 2> /dev/null || echo 0)

    # Set the color based on the status, using color variables.
    if [[ $unstaged == true ]]; then
      color="${CLR_GIT_UNSTAGED}"
    elif [[ $staged == true ]]; then
      color="${CLR_GIT_STAGED}"
    elif [[ $unpushed -gt 0 ]]; then
      color="${CLR_GIT_UNPUSHED}"
    else
      color="${CLR_GIT_CLEAN}"
    fi
    hook_com[branch]="${color}${hook_com[branch]}${CLR_RESET}"
  fi
}

# ----------------------------------------------------------------------------

# --- Worktree Color Function (Using Variables) ---

# Function to determine the path color based on worktree status.
get_path_color() {
  # Check if we're inside a Git worktree.
  if git rev-parse --is-inside-work-tree &> /dev/null; then
    # Check for the specific worktree file pattern ('gitdir:' inside a .git file).
    if [[ -f .git && $(cat .git) == gitdir:* ]]; then
      echo "$CLR_PATH_WORKTREE"
      return
    fi
  fi
  
  # Return the default color if not a worktree.
  echo "$CLR_PATH_DEFAULT"
}

# ----------------------------------------------------------------------------

# --- Hook Registration ---
zstyle ':vcs_info:git*+set-message:*' hooks git-color-branch git-untracked

# --- Prompt Configuration ---

precmd() {
  # Call the encapsulated function and export the result for the PROMPT to use.
  export path_color=$(get_path_color)
  
  # Call vcs_info to gather the Git status.
  vcs_info
}

# This option ensures that the prompt string is re-evaluated each time.
setopt PROMPT_SUBST

# Define the prompt string using the color variables.
PROMPT='${CLR_TIME}%*%f ${path_color}%~%f ${vcs_info_msg_0_} ${vcs_info_msg_1_}$ '

### Confirmation
echo "Loaded prompt layout"