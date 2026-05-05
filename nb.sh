###
### nb: navigate, open, and run an Xcode project across git worktrees.
###
### Required environment (typically exported in private-commands.sh):
###   NB_PROJECT             Project name (matches <NB_PROJECT>.xcodeproj basename
###                          and the Xcode scheme).
###   NB_ROOT                Absolute path to the main worktree.
###
### Optional environment (only consulted by `nb run` flows):
###   NB_BUNDLE_ID           App bundle id (used by `nb run --current` actions).
###   NB_SIM_DEVICE_ID       UDID of an iOS Simulator (used by `nb run [sim]`).
###   NB_PHYSICAL_DEVICE_ID  UDID of a paired physical device (used by
###                          `nb run physical`).
###   NB_RECORD_DIR          Default output directory for screen recordings
###                          (defaults to ~/Documents/Pictures/Screenshots).
###

#
# Usage:
#   nb                              Navigate to the main worktree.
#   nb <worktree>                   Navigate to a worktree by alias or basename.
#   nb nav [<worktree>]             Same as above; `nav` is explicit.
#   nb open [<worktree>]            Open the Xcode project without navigating.
#                                   With no arg, defaults to the worktree you're
#                                   currently inside (falling back to the main
#                                   worktree if you're outside the project).
#   nb run [physical|sim] [<worktree>]
#                                   Build the iOS app from <worktree>/ios and run
#                                   it on a destination. With no worktree arg,
#                                   behaves like `open`. `sim` (default) requires
#                                   NB_SIM_DEVICE_ID; `physical` requires
#                                   NB_PHYSICAL_DEVICE_ID.
#   nb run [physical|sim] --current {logs|stop|record [<output>]}
#                                   Operate on the currently running app
#                                   (no build). Default mode is `sim`.
#                                     logs    sim: stream unified-log output for
#                                             the project process. physical:
#                                             prints CLI options (lldb attach,
#                                             Console.app, idevicesyslog).
#                                     stop    terminate the running app
#                                             (sim: simctl terminate; physical:
#                                             devicectl process terminate).
#                                     record  sim: record screen video; default
#                                             output is $NB_RECORD_DIR/<project>-<ts>.mp4.
#                                             physical: not supported (xcrun has
#                                             no physical-device recording).
#                                   Both stop and physical-logs lookup require
#                                   NB_BUNDLE_ID.
#   nb add <alias> <worktree-path>  Create/replace an alias for a worktree.
#                                   Each worktree can have at most one alias; if
#                                   <worktree-path> already has an alias, it is
#                                   replaced. If <alias> is already in use, that
#                                   prior mapping is overwritten. <worktree-path>
#                                   may be a full path or just the basename.
#   nb remove <alias>               Delete an alias.
#
# Any argument after `nb` that isn't `open`, `nav`, `run`, `add`, or `remove`
# is treated as an implicit `nav <worktree>`.
#
# Aliases are persisted in ~/.nb_aliases as tab-separated `alias<TAB>worktree`
# pairs, managed via add/remove.
#
# When a lookup fails, the available-worktrees listing includes each
# worktree's alias (if any) in brackets.

nb() {
  if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    cat <<'EOF'
nb — navigate, open, and run an Xcode project across git worktrees.

Usage:
  nb [<worktree>]                     Navigate to <worktree> (or main if omitted).
  nb nav [<worktree>]                 Same as above; explicit form.
  nb open [<worktree>]                Open the Xcode project in Xcode. With no
                                      arg, defaults to the worktree you're
                                      currently inside (else main).
  nb run [physical|sim] [<worktree>]  Build the iOS app from <worktree>/ios and
                                      run it. Default mode is `sim`.
  nb run [physical|sim] --current {logs|stop|record [<output>]}
                                      Operate on the currently running app
                                      (no build). Default mode is `sim`.
                                        logs    sim: stream unified-log output;
                                                physical: prints CLI options.
                                        stop    terminate the running app.
                                        record  sim only; default output is
                                                $NB_RECORD_DIR/<project>-<ts>.mp4.
  nb add <alias> <worktree-path>      Create/replace an alias for a worktree.
  nb remove <alias>                   Delete an alias.
  nb --help, -h                       Show this help.

Any top-level arg that isn't a known subcommand is treated as `nav <worktree>`.
Aliases are persisted in ~/.nb_aliases as tab-separated pairs.

Environment:
  Required:
    NB_PROJECT             Project name (matches <NB_PROJECT>.xcodeproj and scheme).
    NB_ROOT                Absolute path to the main worktree.

  Optional (used by `nb run` flows):
    NB_BUNDLE_ID           App bundle id (used by `nb run --current` actions).
    NB_SIM_DEVICE_ID       UDID of an iOS Simulator (used by `nb run [sim]`).
    NB_PHYSICAL_DEVICE_ID  UDID of a paired physical device.
    NB_RECORD_DIR          Default output directory for screen recordings
                           (defaults to ~/Documents/Pictures/Screenshots).
EOF
    return 0
  fi

  local project="${NB_PROJECT:-}"
  if [ -z "$project" ]; then
    echo "nb: NB_PROJECT is not set. Define it (and NB_ROOT) in private-commands.sh." >&2
    return 1
  fi

  local root="${NB_ROOT:-}"
  if [ -z "$root" ]; then
    echo "nb: NB_ROOT is not set. Define the absolute path to the main worktree." >&2
    return 1
  fi

  local aliases_file="$HOME/.nb_aliases"
  [ -f "$aliases_file" ] || : > "$aliases_file"

  typeset -A wt_aliases
  local _k _v
  while IFS=$'\t' read -r _k _v; do
    [ -z "$_k" ] && continue
    wt_aliases[$_k]="$_v"
  done < "$aliases_file"

  # `add` subcommand: each worktree gets at most one alias
  if [ "$1" = "add" ]; then
    shift
    if [ $# -ne 2 ]; then
      echo "Usage: nb add <alias> <worktree-path>"
      return 1
    fi
    local new_alias="$1"
    local new_worktree
    new_worktree="$(basename "$2")"

    local tmp
    tmp="$(mktemp)" || return 1
    local replaced_alias=""
    while IFS=$'\t' read -r _k _v; do
      [ -z "$_k" ] && continue
      if [ "$_k" = "$new_alias" ] || [ "$_v" = "$new_worktree" ]; then
        [ "$_v" = "$new_worktree" ] && [ "$_k" != "$new_alias" ] && replaced_alias="$_k"
        continue
      fi
      printf '%s\t%s\n' "$_k" "$_v" >> "$tmp"
    done < "$aliases_file"
    printf '%s\t%s\n' "$new_alias" "$new_worktree" >> "$tmp"
    mv "$tmp" "$aliases_file"

    if [ -n "$replaced_alias" ]; then
      echo "Replaced alias for $new_worktree: $replaced_alias -> $new_alias"
    else
      echo "Added alias: $new_alias -> $new_worktree"
    fi
    return 0
  fi

  # `remove` subcommand: drop an alias by name
  if [ "$1" = "remove" ]; then
    shift
    if [ $# -ne 1 ]; then
      echo "Usage: nb remove <alias>"
      return 1
    fi
    local rm_alias="$1"
    if [ -z "${wt_aliases[$rm_alias]}" ]; then
      echo "Alias not found: $rm_alias"
      return 1
    fi
    local rm_worktree="${wt_aliases[$rm_alias]}"

    local tmp
    tmp="$(mktemp)" || return 1
    while IFS=$'\t' read -r _k _v; do
      [ -z "$_k" ] && continue
      [ "$_k" = "$rm_alias" ] && continue
      printf '%s\t%s\n' "$_k" "$_v" >> "$tmp"
    done < "$aliases_file"
    mv "$tmp" "$aliases_file"
    echo "Removed alias: $rm_alias -> $rm_worktree"
    return 0
  fi

  local action="nav"
  if [ $# -gt 0 ]; then
    case "$1" in
      open|nav|run)
        action="$1"
        shift
        ;;
    esac
  fi

  local run_target_mode="sim"
  if [ "$action" = "run" ] && [ $# -gt 0 ]; then
    case "$1" in
      physical)
        run_target_mode="physical"
        shift
        ;;
      sim|simulator)
        run_target_mode="sim"
        shift
        ;;
    esac
  fi

  # `nb run [physical|sim] --current {logs|stop|record}`: operate on the
  # currently booted sim or paired physical device. No worktree / no build.
  if [ "$action" = "run" ] && [ "$1" = "--current" ]; then
    shift
    local sub="${1:-}"
    [ $# -gt 0 ] && shift

    local bundle_id="${NB_BUNDLE_ID:-}"
    if [ -z "$bundle_id" ]; then
      echo "nb: NB_BUNDLE_ID is not set; --current actions need it to identify the app." >&2
      return 1
    fi

    if [ "$run_target_mode" = "physical" ]; then
      local device_id="${NB_PHYSICAL_DEVICE_ID:-}"
      if [ -z "$device_id" ]; then
        echo "nb: NB_PHYSICAL_DEVICE_ID is not set." >&2
        return 1
      fi

      case "$sub" in
        logs)
          echo "Streaming logs from a physical device isn't supported by xcrun directly."
          echo "Options:"
          echo "  - Attach lldb to the running process; stdio appears in lldb's console:"
          echo "      lldb -p <PID>"
          echo "  - Open Console.app, select the device in the sidebar, filter to '$project':"
          echo "      open -a Console"
          echo "  - Install idevicesyslog and run:"
          echo "      brew install libimobiledevice && idevicesyslog -u $device_id | grep -i $project"
          return 1
          ;;
        stop)
          # Look up the PID of the running app via devicectl, then terminate.
          local pid
          pid="$(xcrun devicectl device info processes --device "$device_id" --json-output - 2>/dev/null | \
            NB_PROJ="$project" NB_BUNDLE="$bundle_id" python3 -c '
import json, os, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
proj = os.environ["NB_PROJ"].lower()
bundle = os.environ["NB_BUNDLE"].lower()
result = data.get("result", {})
for p in result.get("runningProcesses", []):
    exe = (p.get("executable") or "").lower()
    bid = (p.get("bundleIdentifier") or "").lower()
    if bundle and bid == bundle:
        print(p.get("processIdentifier", "")); sys.exit(0)
    if proj and proj in exe:
        print(p.get("processIdentifier", "")); sys.exit(0)
')"
          if [ -z "$pid" ]; then
            echo "No running $project process found on physical device $device_id"
            return 1
          fi
          echo "Terminating $project (PID $pid) on physical device"
          xcrun devicectl device process terminate --device "$device_id" --pid "$pid"
          ;;
        record)
          echo "Screen recording isn't available via xcrun for physical devices."
          echo "Use Xcode > Window > Devices and Simulators (record button on the device row),"
          echo "or QuickTime Player > File > New Movie Recording > pick the iPad as camera."
          return 1
          ;;
        ""|*)
          echo "Usage: nb run physical --current {logs|stop}"
          return 1
          ;;
      esac
      return $?
    fi

    case "$sub" in
      logs)
        echo "Streaming log for $project on booted simulator (Ctrl+C to stop)"
        xcrun simctl spawn booted log stream --process "$project"
        ;;
      stop)
        echo "Terminating $bundle_id on booted simulator"
        xcrun simctl terminate booted "$bundle_id"
        ;;
      record)
        local out="${1:-}"
        if [ -z "$out" ]; then
          local rec_dir="${NB_RECORD_DIR:-$HOME/Documents/Pictures/Screenshots}"
          mkdir -p "$rec_dir" || return 1
          out="$rec_dir/${project}-$(date +%Y%m%d-%H%M%S).mp4"
        fi
        echo "Recording booted simulator to: $out"
        echo "(Press Ctrl+C to stop and save.)"
        xcrun simctl io booted recordVideo "$out"
        ;;
      ""|*)
        echo "Usage: nb run [sim] --current {logs|stop|record [<output>]}"
        return 1
        ;;
    esac
    return $?
  fi

  local target="$root"
  local worktree=""
  local requested_worktree=""

  if [ $# -gt 1 ]; then
    echo "Usage: nb [open|nav] [<worktree>]  |  nb run [physical|sim] [<worktree>]  |  nb add <alias> <worktree-path>  |  nb remove <alias>  (see: nb --help)"
    return 1
  fi

  if [ $# -eq 1 ]; then
    requested_worktree="$1"
    shift
  fi

  # `nb open|run` with no arg defaults to the worktree we're currently inside,
  # provided it's a registered worktree of NB_ROOT's repo (so sibling-path
  # worktrees like `git worktree add ../feature` work too).
  if { [ "$action" = "open" ] || [ "$action" = "run" ]; } && [ -z "$requested_worktree" ]; then
    local cwd_toplevel
    cwd_toplevel="$(git rev-parse --show-toplevel 2>/dev/null)"
    if [ -n "$cwd_toplevel" ]; then
      local _wt_line _wt_path
      while IFS= read -r _wt_line; do
        case "$_wt_line" in
          "worktree "*)
            _wt_path="${_wt_line#worktree }"
            if [ "$_wt_path" = "$cwd_toplevel" ]; then
              target="$cwd_toplevel"
              local _cwd_base
              _cwd_base="$(basename "$cwd_toplevel")"
              [ "$_cwd_base" != "$project" ] && worktree="$_cwd_base"
              break
            fi
            ;;
        esac
      done < <(git -C "$root" worktree list --porcelain 2>/dev/null)
    fi
  fi

  if [ -n "$requested_worktree" ]; then
    # translate alias if one exists; otherwise use the raw value
    if [ -n "${wt_aliases[$requested_worktree]}" ]; then
      worktree="${wt_aliases[$requested_worktree]}"
    else
      worktree="$requested_worktree"
    fi

    if [ ! -d "$root/.git" ] && [ ! -f "$root/.git" ]; then
      echo "Not a git repo: $root"
      return 1
    fi

    local found=""
    local current_path=""

    while IFS= read -r line; do
      case "$line" in
        worktree\ *)
          current_path="${line#worktree }"
          local base
          base="$(basename "$current_path")"

          if [ "$base" = "$worktree" ]; then
            found="$current_path"
            break
          fi
          ;;
      esac
    done < <(git -C "$root" worktree list --porcelain)

    if [ -z "$found" ]; then
      echo "Worktree not found: $requested_worktree"
      [ "$requested_worktree" != "$worktree" ] && echo "Alias resolved to: $worktree"
      echo
      echo "Available worktrees:"

      typeset -A _wt_rev
      local _a
      for _a in "${(@k)wt_aliases}"; do
        _wt_rev[${wt_aliases[$_a]}]="$_a"
      done

      local _line _wt_path _wt_base
      while IFS= read -r _line; do
        _wt_path="${_line%% *}"
        _wt_base="$(basename "$_wt_path")"
        if [ -n "${_wt_rev[$_wt_base]}" ]; then
          echo "$_line  [alias: ${_wt_rev[$_wt_base]}]"
        else
          echo "$_line"
        fi
      done < <(git -C "$root" worktree list)
      return 1
    fi

    target="$found"
  fi

  if [ ! -d "$target" ]; then
    echo "Directory not found: $target"
    return 1
  fi

  # Build human-readable action text
  local action_text=""
  case "$action" in
    nav) action_text="Navigating to" ;;
    open) action_text="Opening" ;;
    run) action_text="Running" ;;
    *) action_text="Running unknown action on" ;;
  esac

  # Build location description
  local location_text=""
  if [ -n "$worktree" ]; then
    location_text="worktree '$worktree'"
  else
    location_text="main worktree"
  fi

  if [ "$action" != "run" ]; then
    echo "$action_text $project at $location_text"
  fi

  case "$action" in
    nav)
      cd "$target" || return 1
      ;;
    open)
      local xcodeproj="$target/ios/${project}.xcodeproj"
      if [ ! -d "$xcodeproj" ]; then
        echo "Xcode project not found: $xcodeproj"
        return 1
      fi
      xed "$xcodeproj"
      ;;
    run)
      local ios_dir="$target/ios"
      local xcodeproj="$ios_dir/${project}.xcodeproj"
      if [ ! -d "$xcodeproj" ]; then
        echo "Xcode project not found: $xcodeproj"
        return 1
      fi

      local device_id device_label destination

      if [ "$run_target_mode" = "physical" ]; then
        device_id="${NB_PHYSICAL_DEVICE_ID:-}"
        if [ -z "$device_id" ]; then
          echo "nb: NB_PHYSICAL_DEVICE_ID is not set." >&2
          return 1
        fi

        # Look up the device's friendly name from devicectl. Best effort —
        # if the device isn't paired/visible, we'll fall back to the UDID.
        device_label="$(xcrun devicectl list devices --json-output - 2>/dev/null | \
          NB_DEV_ID="$device_id" python3 -c '
import json, os, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
target = os.environ["NB_DEV_ID"].lower()

def find(obj):
    if isinstance(obj, dict):
        hp = obj.get("hardwareProperties") if isinstance(obj.get("hardwareProperties"), dict) else {}
        udid = hp.get("udid", "") if isinstance(hp.get("udid", ""), str) else ""
        if udid.lower() == target:
            dp = obj.get("deviceProperties") if isinstance(obj.get("deviceProperties"), dict) else {}
            name = (dp.get("name") if isinstance(dp, dict) else None) or obj.get("name")
            if name:
                return name
        for v in obj.values():
            r = find(v)
            if r: return r
    elif isinstance(obj, list):
        for v in obj:
            r = find(v)
            if r: return r
    return None

n = find(data)
if n: print(n)
')"
        [ -z "$device_label" ] && device_label="physical device $device_id"

        destination="id=$device_id,platform=iOS"

        echo "$action_text $project at $location_text on physical device: $device_label"
      else
        device_id="${NB_SIM_DEVICE_ID:-}"
        if [ -z "$device_id" ]; then
          echo "nb: NB_SIM_DEVICE_ID is not set." >&2
          return 1
        fi

        # Look up the simulator's name + runtime + state by UDID.
        local sim_info
        sim_info="$(xcrun simctl list devices --json 2>/dev/null | \
          NB_DEV_ID="$device_id" python3 -c '
import json, os, sys
data = json.load(sys.stdin)
target = os.environ["NB_DEV_ID"].lower()
for runtime, devs in data.get("devices", {}).items():
    for d in devs:
        if d.get("udid", "").lower() == target:
            print(d.get("name", ""))
            print(runtime)
            print(d.get("state", ""))
            sys.exit(0)
')"
        if [ -z "$sim_info" ]; then
          echo "Simulator not found: $device_id"
          echo "Pick a UDID from 'xcrun simctl list devices' and set NB_SIM_DEVICE_ID."
          return 1
        fi

        local sim_name="${sim_info%%$'\n'*}"
        local _rest="${sim_info#*$'\n'}"
        local sim_runtime_id="${_rest%%$'\n'*}"
        local sim_state="${_rest##*$'\n'}"

        local runtime_label
        runtime_label="$(xcrun simctl list runtimes --json 2>/dev/null | \
          NB_RT_ID="$sim_runtime_id" python3 -c '
import json, os, sys
data = json.load(sys.stdin)
target = os.environ["NB_RT_ID"]
for r in data.get("runtimes", []):
    if r.get("identifier") == target:
        print(r.get("name", target))
        break
')"
        [ -z "$runtime_label" ] && runtime_label="$sim_runtime_id"

        device_label="$sim_name — $runtime_label"
        destination="id=$device_id"

        echo "$action_text $project at $location_text on simulator: $device_label"

        if [ "$sim_state" != "Booted" ]; then
          echo "Booting simulator $device_id"
          xcrun simctl boot "$device_id" 2>/dev/null
        fi
        open -a Simulator
      fi

      echo "Building $project (Debug)"
      if ! xcodebuild \
        -project "$xcodeproj" \
        -scheme "$project" \
        -configuration Debug \
        -destination "$destination" \
        build; then
        echo "Build failed"
        return 1
      fi

      # Resolve the built .app path from Xcode's default DerivedData location
      # via build settings, so it matches what Xcode's "Run" produces.
      local app_path
      app_path="$(xcodebuild \
        -project "$xcodeproj" \
        -scheme "$project" \
        -configuration Debug \
        -destination "$destination" \
        -showBuildSettings -json 2>/dev/null | python3 -c '
import json, os, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for entry in data:
    bs = entry.get("buildSettings", {})
    bp, wn = bs.get("BUILT_PRODUCTS_DIR"), bs.get("WRAPPER_NAME")
    if bp and wn:
        print(os.path.join(bp, wn))
        sys.exit(0)
')"
      if [ -z "$app_path" ] || [ ! -d "$app_path" ]; then
        echo "Built app not found at: ${app_path:-<unknown>}"
        return 1
      fi

      local bundle_id
      bundle_id="$(plutil -extract CFBundleIdentifier raw "$app_path/Info.plist" 2>/dev/null)"
      if [ -z "$bundle_id" ] || [ "$bundle_id" = "-" ]; then
        echo "Could not determine bundle identifier from $app_path/Info.plist"
        return 1
      fi

      if [ "$run_target_mode" = "physical" ]; then
        echo "Installing $bundle_id"
        xcrun devicectl device install app --device "$device_id" "$app_path" || return 1

        # Capture launch output as JSON so we can pull the PID for lldb attach.
        echo "Launching $bundle_id"
        local launch_output launch_status
        launch_output="$(xcrun devicectl device process launch --device "$device_id" --json-output - "$bundle_id" 2>&1)"
        launch_status=$?
        if [ $launch_status -ne 0 ]; then
          echo "$launch_output"
          return $launch_status
        fi
        local pid
        pid="$(printf '%s' "$launch_output" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
process = data.get("result", {}).get("process", {})
pid = process.get("processIdentifier")
if pid is not None:
    print(pid)
')"
        if [ -n "$pid" ]; then
          echo "$bundle_id: $pid"
          echo "Attach with: lldb -p $pid"
        else
          echo "(launched, but PID not found in devicectl output)"
        fi
      else
        echo "Installing $bundle_id"
        xcrun simctl install "$device_id" "$app_path" || return 1

        echo "Launching $bundle_id"
        xcrun simctl launch "$device_id" "$bundle_id"
      fi
      ;;
    *)
      echo "Usage: nb [open|nav] [<worktree>]  |  nb run [physical|sim] [<worktree>]  |  nb add <alias> <worktree-path>  |  nb remove <alias>  (see: nb --help)"
      return 1
      ;;
  esac
}
