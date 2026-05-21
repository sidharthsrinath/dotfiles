#!/usr/bin/env bash
# Wraps gitmux and strips the stashed-changes indicator (⚑ N) from the output.
# Stash entry is rendered as `#[fg=cyan,bold]⚑ N` with an optional trailing
# space when followed by another flag. Strip both forms.
gitmux -cfg "$(dirname "$0")/gitmux.conf" "$1" | sed -E 's/#\[fg=cyan,bold\]⚑ [0-9]+ ?//'
