#!/bin/bash
# Claude Code statusline: dir │ git branch │ model │ session cost │ context used
# Uses ANSI color names so it inherits the terminal palette, matching the
# color vocabulary of tmux.conf and vcs_info_prompt.zsh.

input=$(cat)

IFS=$'\t' read -r model cwd cost ctx_pct <<< "$(echo "$input" | jq -r \
    '[.model.display_name,
      .workspace.current_dir,
      (.cost.total_cost_usd // 0),
      (.context_window.used_percentage // 0)] | @tsv')"

# ANSI codes: green=32, yellow=33, blue=34, red=31, brightblack=90
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
RED=$'\033[31m'
DIM=$'\033[90m'
RESET=$'\033[0m'

line="${GREEN}${cwd##*/}${RESET}"

branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
if [ -n "$branch" ]; then
    line+=" ${DIM}│${RESET} ${BLUE}${branch}${RESET}"
fi

line+=" ${DIM}│ ${model}${RESET}"

ctx_pct=${ctx_pct%.*}
if   [ "$ctx_pct" -ge 80 ]; then ctx_color=$RED
elif [ "$ctx_pct" -ge 50 ]; then ctx_color=$YELLOW
else                             ctx_color=$DIM
fi
line+=" ${DIM}│${RESET} ${ctx_color}${ctx_pct}% ctx${RESET}"

line+=" ${DIM}│${RESET} $(printf '$%.2f' "$cost")"

printf '%s' "$line"
