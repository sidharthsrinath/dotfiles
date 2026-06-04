#!/usr/bin/env bash
#
# Unit tests for ../install.sh helpers.
#
# Run with:
#   ~/dotfiles/tests/test_install.sh
#
# Each test runs with HOME pointed at a fresh tempdir so filesystem operations
# are sandboxed. External commands (brew, curl, git) are replaced by stubs so
# no real installations happen.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SH="$SCRIPT_DIR/../install.sh"

[[ -f "$INSTALL_SH" ]] || { echo "install.sh not found at $INSTALL_SH" >&2; exit 1; }

DOTFILES_TEST_SOURCING=1 source "$INSTALL_SH"

# Silence helper output so test results are readable.
info()    { :; }
success() { :; }

PASS=0
FAIL=0
FAIL_MSGS=()
CURRENT_TEST=""

# ── framework ────────────────────────────────────────────────────────────────

setup() {
  TEST_HOME="$(mktemp -d -t install-tests.XXXXXX)"
  export HOME="$TEST_HOME"
  BREW_INSTALL_CALLS=()
  MOCK_INSTALLED_FORMULA=()
  MOCK_INSTALLED_CASKS=()
}

teardown() {
  if [[ -n "${TEST_HOME:-}" && -d "$TEST_HOME" && "$TEST_HOME" == */install-tests.* ]]; then
    rm -rf "$TEST_HOME"
  fi
  unset TEST_HOME
}

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

assert_false() {
  local rc="$1" msg="${2:-false}"
  if [[ "$rc" -ne 0 ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAIL_MSGS+=("[$CURRENT_TEST] $msg: expected non-zero exit, got 0")
  fi
}

assert_contains() {
  local needle="$1" haystack="$2" msg="${3:-contains}"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAIL_MSGS+=("[$CURRENT_TEST] $msg: '$needle' not found in: $haystack")
  fi
}

assert_not_contains() {
  local needle="$1" haystack="$2" msg="${3:-not_contains}"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAIL_MSGS+=("[$CURRENT_TEST] $msg: did not expect '$needle' in: $haystack")
  fi
}

assert_symlink_to() {
  local expected_target="$1" link="$2" msg="${3:-symlink_target}"
  if [[ -L "$link" && "$(readlink "$link")" == "$expected_target" ]]; then
    PASS=$((PASS + 1))
  else
    local actual
    actual="$(readlink "$link" 2>/dev/null || echo "<not a symlink>")"
    FAIL=$((FAIL + 1))
    FAIL_MSGS+=("[$CURRENT_TEST] $msg: expected symlink to '$expected_target', got '$actual'")
  fi
}

assert_file_exists() {
  local path="$1" msg="${2:-file_exists}"
  if [[ -e "$path" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAIL_MSGS+=("[$CURRENT_TEST] $msg: '$path' does not exist")
  fi
}

assert_file_not_exists() {
  local path="$1" msg="${2:-file_not_exists}"
  if [[ ! -e "$path" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAIL_MSGS+=("[$CURRENT_TEST] $msg: '$path' should not exist")
  fi
}

# ── brew stub ────────────────────────────────────────────────────────────────
#
# Tests populate MOCK_INSTALLED_FORMULA and MOCK_INSTALLED_CASKS.
# brew_install calls are recorded in BREW_INSTALL_CALLS.

brew() {
  case "$1" in
    list)
      local flag="$2" pkg="$3"
      if [[ "$flag" == "--formula" ]]; then
        for p in "${MOCK_INSTALLED_FORMULA[@]:-}"; do
          [[ "$p" == "$pkg" ]] && return 0
        done
        return 1
      elif [[ "$flag" == "--cask" ]]; then
        for p in "${MOCK_INSTALLED_CASKS[@]:-}"; do
          [[ "$p" == "$pkg" ]] && return 0
        done
        return 1
      fi
      return 1
      ;;
    install)
      BREW_INSTALL_CALLS+=("${*:2}")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# ── safe_link tests ───────────────────────────────────────────────────────────

test_safe_link_creates_symlink() {
  local src="$TEST_HOME/src_file" dest="$TEST_HOME/dest_link"
  touch "$src"
  safe_link "$src" "$dest"
  assert_symlink_to "$src" "$dest" "symlink created"
}

test_safe_link_creates_parent_dirs() {
  local src="$TEST_HOME/src_file" dest="$TEST_HOME/a/b/c/dest_link"
  touch "$src"
  safe_link "$src" "$dest"
  assert_symlink_to "$src" "$dest" "symlink in nested dir"
  assert_file_exists "$TEST_HOME/a/b/c" "parent dirs created"
}

test_safe_link_backs_up_existing_file() {
  local src="$TEST_HOME/src_file" dest="$TEST_HOME/dest_file"
  touch "$src"
  echo "original content" > "$dest"
  safe_link "$src" "$dest"
  assert_symlink_to "$src" "$dest" "symlink replaces file"
  assert_file_exists "$dest.bak" "backup created"
  local bak_content
  bak_content="$(cat "$dest.bak")"
  assert_eq "original content" "$bak_content" "backup preserves content"
}

test_safe_link_idempotent_if_correct() {
  local src="$TEST_HOME/src_file" dest="$TEST_HOME/dest_link"
  touch "$src"
  safe_link "$src" "$dest"
  # Call again — should not create .bak or change anything
  safe_link "$src" "$dest"
  assert_symlink_to "$src" "$dest" "symlink still correct"
  assert_file_not_exists "$dest.bak" "no spurious backup on re-run"
}

test_safe_link_replaces_wrong_symlink() {
  local src="$TEST_HOME/src_file" wrong="$TEST_HOME/wrong_target" dest="$TEST_HOME/dest_link"
  touch "$src" "$wrong"
  ln -sf "$wrong" "$dest"
  safe_link "$src" "$dest"
  assert_symlink_to "$src" "$dest" "symlink updated to new target"
  assert_file_exists "$dest.bak" "old symlink backed up"
}

test_safe_link_does_not_overwrite_backup_if_no_existing_file() {
  local src="$TEST_HOME/src_file" dest="$TEST_HOME/dest_link"
  touch "$src"
  safe_link "$src" "$dest"
  assert_file_not_exists "$dest.bak" "no backup when dest did not exist"
}

# ── append_source tests ───────────────────────────────────────────────────────

test_append_source_creates_rc_and_appends() {
  local rc="$TEST_HOME/.zshrc" src_path="/some/dotfiles/shell/zshrc"
  # rc does not exist yet
  append_source "$rc" "$src_path"
  assert_file_exists "$rc" "rc file created"
  local content
  content="$(cat "$rc")"
  assert_contains "source $src_path" "$content" "source line written"
}

test_append_source_appends_to_existing_rc() {
  local rc="$TEST_HOME/.zshrc" src_path="/some/dotfiles/shell/zshrc"
  echo "export FOO=bar" > "$rc"
  append_source "$rc" "$src_path"
  local content
  content="$(cat "$rc")"
  assert_contains "export FOO=bar" "$content" "existing content preserved"
  assert_contains "source $src_path" "$content" "source line appended"
}

test_append_source_does_not_duplicate() {
  local rc="$TEST_HOME/.zshrc" src_path="/some/dotfiles/shell/zshrc"
  echo "source $src_path" > "$rc"
  append_source "$rc" "$src_path"
  append_source "$rc" "$src_path"
  local count
  count="$(grep -c "source $src_path" "$rc")"
  assert_eq "1" "$count" "source line not duplicated"
}

test_append_source_handles_empty_rc() {
  local rc="$TEST_HOME/.zshrc" src_path="/dotfiles/shell/zshrc"
  touch "$rc"
  append_source "$rc" "$src_path"
  local content
  content="$(cat "$rc")"
  assert_contains "source $src_path" "$content" "source line added to empty file"
}

test_append_source_does_not_add_partial_match() {
  # A path that is a substring of the real path should not count as present.
  local rc="$TEST_HOME/.zshrc" src_path="/dotfiles/shell/zshrc"
  echo "source /dotfiles/shell/zshrc_old" > "$rc"
  append_source "$rc" "$src_path"
  local content
  content="$(cat "$rc")"
  assert_contains "source $src_path" "$content" "exact path added despite substring match"
}

# ── brew_install tests ────────────────────────────────────────────────────────

test_brew_install_skips_when_formula_installed() {
  MOCK_INSTALLED_FORMULA=("tmux")
  BREW_INSTALL_CALLS=()
  brew_install tmux
  assert_eq "0" "${#BREW_INSTALL_CALLS[@]}" "brew install not called when already installed"
}

test_brew_install_calls_brew_when_missing() {
  MOCK_INSTALLED_FORMULA=()
  MOCK_INSTALLED_CASKS=()
  BREW_INSTALL_CALLS=()
  brew_install tmux
  assert_eq "1" "${#BREW_INSTALL_CALLS[@]}" "brew install called once"
  assert_eq "tmux" "${BREW_INSTALL_CALLS[0]}" "correct package passed"
}

test_brew_install_skips_when_cask_installed() {
  MOCK_INSTALLED_CASKS=("ghostty")
  BREW_INSTALL_CALLS=()
  brew_install --cask ghostty
  assert_eq "0" "${#BREW_INSTALL_CALLS[@]}" "brew install not called for installed cask"
}

test_brew_install_passes_extra_args() {
  MOCK_INSTALLED_FORMULA=()
  MOCK_INSTALLED_CASKS=()
  BREW_INSTALL_CALLS=()
  brew_install --cask ghostty
  assert_eq "1" "${#BREW_INSTALL_CALLS[@]}" "brew install called"
  assert_contains "--cask" "${BREW_INSTALL_CALLS[0]}" "cask flag forwarded"
  assert_contains "ghostty" "${BREW_INSTALL_CALLS[0]}" "package name forwarded"
}

# ── runner ────────────────────────────────────────────────────────────────────

tests=(
  test_safe_link_creates_symlink
  test_safe_link_creates_parent_dirs
  test_safe_link_backs_up_existing_file
  test_safe_link_idempotent_if_correct
  test_safe_link_replaces_wrong_symlink
  test_safe_link_does_not_overwrite_backup_if_no_existing_file
  test_append_source_creates_rc_and_appends
  test_append_source_appends_to_existing_rc
  test_append_source_does_not_duplicate
  test_append_source_handles_empty_rc
  test_append_source_does_not_add_partial_match
  test_brew_install_skips_when_formula_installed
  test_brew_install_calls_brew_when_missing
  test_brew_install_skips_when_cask_installed
  test_brew_install_passes_extra_args
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
