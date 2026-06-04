#!/usr/bin/env bash
#
# Integration tests for ../install.sh
#
# Run with:
#   ~/dotfiles/tests/test_install_integration.sh
#
# Simulates a fresh machine install by running install.sh end-to-end inside a
# sandboxed temp HOME. A minimal dotfiles fixture is created in the sandbox so
# symlink targets exist. External commands (brew, git, curl, nb) are replaced
# by stub binaries so no real software is installed and no network calls are
# made.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SH="$SCRIPT_DIR/../install.sh"

[[ -f "$INSTALL_SH" ]] || { echo "install.sh not found at $INSTALL_SH" >&2; exit 1; }

PASS=0
FAIL=0
FAIL_MSGS=()
CURRENT_TEST=""

SANDBOX_HOME=""
SANDBOX_DOTFILES=""
STUB_BIN=""

# ── framework ─────────────────────────────────────────────────────────────────

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-eq}"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAIL_MSGS+=("[$CURRENT_TEST] $msg: expected '$expected', got '$actual'")
  fi
}

assert_true() {
  local rc="$1" msg="${2:-true}"
  if [[ "$rc" -eq 0 ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAIL_MSGS+=("[$CURRENT_TEST] $msg: expected exit 0, got $rc")
  fi
}

assert_contains() {
  local needle="$1" haystack="$2" msg="${3:-contains}"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAIL_MSGS+=("[$CURRENT_TEST] $msg: '$needle' not found in output")
  fi
}

assert_not_contains() {
  local needle="$1" haystack="$2" msg="${3:-not_contains}"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAIL_MSGS+=("[$CURRENT_TEST] $msg: did not expect '$needle' in output")
  fi
}

assert_symlink_to() {
  local expected_target="$1" link="$2" msg="${3:-$(basename "$link")}"
  if [[ -L "$link" && "$(readlink "$link")" == "$expected_target" ]]; then
    PASS=$((PASS + 1))
  else
    local actual
    actual="$(readlink "$link" 2>/dev/null || echo "<not a symlink>")"
    FAIL=$((FAIL + 1))
    FAIL_MSGS+=("[$CURRENT_TEST] $msg: expected link -> '$expected_target', got '$actual'")
  fi
}

assert_not_symlink() {
  local path="$1" msg="${2:-not_symlink}"
  if [[ ! -L "$path" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAIL_MSGS+=("[$CURRENT_TEST] $msg: '$path' should not be a symlink")
  fi
}

assert_file_exists() {
  local path="$1" msg="${2:-$(basename "$path") exists}"
  if [[ -e "$path" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAIL_MSGS+=("[$CURRENT_TEST] $msg: '$path' does not exist")
  fi
}

# ── sandbox ───────────────────────────────────────────────────────────────────

setup() {
  SANDBOX_HOME="$(mktemp -d -t install-integration.XXXXXX)"
  SANDBOX_DOTFILES="$SANDBOX_HOME/dotfiles"
  STUB_BIN="$SANDBOX_HOME/.stubs"

  # Minimal dotfiles fixture — mirrors the paths install.sh symlinks.
  mkdir -p "$SANDBOX_DOTFILES/"{tmux,git,ghostty,nvim,skhd,shell}
  touch "$SANDBOX_DOTFILES/tmux/tmux.conf"
  touch "$SANDBOX_DOTFILES/git/gitconfig"
  touch "$SANDBOX_DOTFILES/ghostty/config"
  touch "$SANDBOX_DOTFILES/skhd/skhdrc"
  touch "$SANDBOX_DOTFILES/shell/zshrc"
  touch "$SANDBOX_DOTFILES/shell/zprofile"
  # private-commands.sh intentionally absent to test that install.sh creates it.

  mkdir -p "$STUB_BIN"

  # brew: nothing pre-installed; logs every call to $HOME/.stub.log
  cat > "$STUB_BIN/brew" << 'STUB'
#!/usr/bin/env bash
echo "brew $*" >> "$HOME/.stub.log"
case "$1" in
  list) exit 1 ;;  # simulate nothing installed
  *)    exit 0 ;;
esac
STUB

  # git: no-op stub (prevents 'git lfs install' from running real git)
  cat > "$STUB_BIN/git" << 'STUB'
#!/usr/bin/env bash
echo "git $*" >> "$HOME/.stub.log"
STUB

  # curl: no-op stub (prevents any network calls)
  cat > "$STUB_BIN/curl" << 'STUB'
#!/usr/bin/env bash
echo "curl $*" >> "$HOME/.stub.log"
STUB

  # nb: exists so 'command -v nb' succeeds, skipping the nb install block
  cat > "$STUB_BIN/nb" << 'STUB'
#!/usr/bin/env bash
STUB

  chmod +x "$STUB_BIN"/{brew,git,curl,nb}
}

teardown() {
  if [[ -n "${SANDBOX_HOME:-}" && "$SANDBOX_HOME" == */install-integration.* ]]; then
    rm -rf "$SANDBOX_HOME"
  fi
  unset SANDBOX_HOME SANDBOX_DOTFILES STUB_BIN
}

# Run install.sh as a subprocess in the sandbox, answering all 7 interactive
# prompts with the given character (default: n = skip all optional tools).
run_install() {
  local answer="${1:-n}"
  local input
  input="$(printf '%s\n' "$answer" "$answer" "$answer" "$answer" "$answer" "$answer" "$answer")"
  HOME="$SANDBOX_HOME" \
  DOTFILES="$SANDBOX_DOTFILES" \
  PATH="$STUB_BIN:$PATH" \
    bash "$INSTALL_SH" <<< "$input" >/dev/null 2>&1
  return $?
}

stub_log() {
  cat "$SANDBOX_HOME/.stub.log" 2>/dev/null
}

# ── tests ─────────────────────────────────────────────────────────────────────

# Config symlinks are created pointing into the dotfiles fixture.
test_symlinks_created_on_fresh_install() {
  local rc
  run_install; rc=$?
  assert_true $rc "install.sh exited successfully"
  assert_symlink_to "$SANDBOX_DOTFILES/tmux/tmux.conf" "$SANDBOX_HOME/.tmux.conf"
  assert_symlink_to "$SANDBOX_DOTFILES/git/gitconfig"  "$SANDBOX_HOME/.gitconfig"
  assert_symlink_to "$SANDBOX_DOTFILES/ghostty/config" "$SANDBOX_HOME/.config/ghostty/config"
  assert_symlink_to "$SANDBOX_DOTFILES/nvim"           "$SANDBOX_HOME/.config/nvim"
  assert_symlink_to "$SANDBOX_DOTFILES/skhd/skhdrc"   "$SANDBOX_HOME/.config/skhd/skhdrc"
}

# Shell config files are created with source lines appended, not symlinked.
test_shell_config_sourced_not_symlinked() {
  run_install
  assert_file_exists "$SANDBOX_HOME/.zshrc"
  assert_file_exists "$SANDBOX_HOME/.zprofile"
  assert_not_symlink "$SANDBOX_HOME/.zshrc"    ".zshrc is a regular file, not a symlink"
  assert_not_symlink "$SANDBOX_HOME/.zprofile" ".zprofile is a regular file, not a symlink"
  assert_contains "source $SANDBOX_DOTFILES/shell/zshrc"    "$(cat "$SANDBOX_HOME/.zshrc")"    "zshrc source line"
  assert_contains "source $SANDBOX_DOTFILES/shell/zprofile" "$(cat "$SANDBOX_HOME/.zprofile")" "zprofile source line"
}

# A pre-existing .zshrc is not overwritten — source line is appended.
test_preserves_existing_zshrc_content() {
  echo 'export EXISTING_VAR=1' > "$SANDBOX_HOME/.zshrc"
  run_install
  local content
  content="$(cat "$SANDBOX_HOME/.zshrc")"
  assert_contains "EXISTING_VAR=1"                           "$content" "existing content preserved"
  assert_contains "source $SANDBOX_DOTFILES/shell/zshrc"    "$content" "source line appended"
}

# The private-commands.sh stub is created when absent.
test_private_commands_stub_created() {
  run_install
  assert_file_exists "$SANDBOX_DOTFILES/shell/private-commands.sh"
}

# brew install is called for every core tool.
test_core_tools_installed_via_brew() {
  run_install
  local log
  log="$(stub_log)"
  assert_contains "brew install tmux"          "$log" "tmux"
  assert_contains "brew install neovim"        "$log" "neovim"
  assert_contains "brew install git-lfs"       "$log" "git-lfs"
  assert_contains "brew install gitmux"        "$log" "gitmux"
  assert_contains "brew install skhd"          "$log" "skhd"
  assert_contains "brew install --cask ghostty" "$log" "ghostty"
}

# git lfs install is called.
test_git_lfs_initialized() {
  run_install
  assert_contains "git lfs install --skip-repo" "$(stub_log)" "git lfs"
}

# Answering n to all prompts makes no curl calls (no network activity).
test_no_network_calls_when_optionals_declined() {
  run_install "n"
  assert_not_contains "curl" "$(stub_log)" "no curl calls"
}

# Running install.sh twice produces no .bak files on the second run.
test_idempotent_no_bak_files_on_rerun() {
  run_install
  run_install
  local bak_count
  bak_count="$(find "$SANDBOX_HOME" -name "*.bak" -not -path "*/.stubs/*" | wc -l | tr -d ' ')"
  assert_eq "0" "$bak_count" "no .bak files after re-run"
}

# Running install.sh twice does not duplicate source lines in shell rc files.
test_idempotent_no_duplicate_source_lines() {
  run_install
  run_install
  local zshrc_count zprofile_count
  zshrc_count="$(grep -c "source $SANDBOX_DOTFILES/shell/zshrc" "$SANDBOX_HOME/.zshrc" 2>/dev/null || echo 0)"
  zprofile_count="$(grep -c "source $SANDBOX_DOTFILES/shell/zprofile" "$SANDBOX_HOME/.zprofile" 2>/dev/null || echo 0)"
  assert_eq "1" "$zshrc_count"    ".zshrc source line not duplicated"
  assert_eq "1" "$zprofile_count" ".zprofile source line not duplicated"
}

# ── runner ────────────────────────────────────────────────────────────────────

tests=(
  test_symlinks_created_on_fresh_install
  test_shell_config_sourced_not_symlinked
  test_preserves_existing_zshrc_content
  test_private_commands_stub_created
  test_core_tools_installed_via_brew
  test_git_lfs_initialized
  test_no_network_calls_when_optionals_declined
  test_idempotent_no_bak_files_on_rerun
  test_idempotent_no_duplicate_source_lines
)

for t in "${tests[@]}"; do
  CURRENT_TEST="$t"
  setup
  $t
  teardown
done

echo
echo "passed: $PASS"
echo "failed: $FAIL"

if (( FAIL > 0 )); then
  echo
  echo "Failures:"
  for msg in "${FAIL_MSGS[@]}"; do
    echo "  - $msg"
  done
  exit 1
fi
