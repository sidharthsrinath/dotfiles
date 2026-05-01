#!/usr/bin/env zsh
# Regenerate skhdrc from the mapping below.
# Run this whenever you change `trigger` or `apps`, then reload skhd.

set -euo pipefail

trigger="cmd + ctrl"

typeset -A apps=(
  b 'open -a "Safari"'
  s 'open -a "Slack"'
  x 'open -b com.apple.dt.Xcode'
  t 'open -a "cmux"'
  n 'open -a "Notion"'
  4 'open ~/Documents/Pictures/Screenshots'
)

out="${0:A:h}/skhdrc"

{
  for letter in "${(@k)apps}"; do
    printf '%s - %s : %s\n' "$trigger" "$letter" "${apps[$letter]}"
  done
} | sort > "$out"

echo "Wrote $out"

if command -v skhd >/dev/null && pgrep -x skhd >/dev/null; then
  skhd --restart-service
  echo "Restarted skhd"
fi
