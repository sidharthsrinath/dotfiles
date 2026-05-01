# TODO

## Window management

Set up `yabai` alongside the existing `skhd` config to get scriptable Spaces + window control.

- Install: `brew install koekeishiya/formulae/yabai`
- Start service: `yabai --install-service && yabai --start-service` (grant Accessibility + Screen Recording when prompted)
- Add a `yabairc` to this repo and symlink it to `~/.yabairc` (same convention as `skhdrc`)
- Decide on SIP: leave SIP fully on for now — basic Space queries (`yabai -m query --spaces`) and most window ops work without disabling it. Revisit only if a needed feature (e.g. moving Spaces, certain window manipulations) requires the scripting addition.
- Wire skhd shortcuts for common ops once yabai is up (focus space N, send window to space N, etc.)
