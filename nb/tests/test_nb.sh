#!/usr/bin/env zsh
#
# Unit tests for ../nb.sh.
#
# Run with:
#   ~/dotfiles/nb/tests/test_nb.sh
#
# Each test runs in the parent shell with HOME pointed at a fresh tempdir and
# all NB_* env vars unset, so the alias file at ~/.nb_aliases is isolated and
# state doesn't leak between tests.
#
# These tests cover the pure-logic surface: env-var validation, alias
# add/remove, and the --current argument router. They do NOT exercise
# xcodebuild, xcrun simctl, xcrun devicectl, plutil, etc. — that path is
# verified by hand against a real iOS toolchain.

SCRIPT_PATH="${(%):-%x}"
REPO_DIR="${SCRIPT_PATH:A:h:h}"
NB_SH="$REPO_DIR/nb.sh"

[[ -f "$NB_SH" ]] || { echo "nb.sh not found at $NB_SH" >&2; exit 1; }

source "$NB_SH"

PASS=0
FAIL=0
typeset -a FAIL_MSGS
CURRENT_TEST=""

# ------------------------------ framework ------------------------------------

setup() {
  TEST_HOME="$(mktemp -d -t nb-tests.XXXXXX)"
  export HOME="$TEST_HOME"
  unset NB_PROJECT NB_ROOT NB_BUNDLE_ID NB_SIM_DEVICE_ID NB_PHYSICAL_DEVICE_ID NB_RECORD_DIR
}

teardown() {
  if [[ -n "${TEST_HOME:-}" && -d "$TEST_HOME" && "$TEST_HOME" == */nb-tests.* ]]; then
    rm -rf "$TEST_HOME"
  fi
  unset TEST_HOME
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-eq}"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAIL_MSGS+=("[$CURRENT_TEST] $msg: expected '$expected', got '$actual'")
  fi
}

assert_contains() {
  local needle="$1" haystack="$2" msg="${3:-contains}"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAIL_MSGS+=("[$CURRENT_TEST] $msg: '$needle' not found in: $haystack")
  fi
}

assert_not_contains() {
  local needle="$1" haystack="$2" msg="${3:-not_contains}"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAIL_MSGS+=("[$CURRENT_TEST] $msg: did not expect '$needle' in: $haystack")
  fi
}

# -------------------------------- tests --------------------------------------

test_missing_project_errors() {
  local out rc
  out="$(nb 2>&1)"; rc=$?
  assert_eq 1 "$rc" "exit code"
  assert_contains "NB_PROJECT" "$out" "error names NB_PROJECT"
}

test_missing_root_errors() {
  export NB_PROJECT=TestApp
  local out rc
  out="$(nb 2>&1)"; rc=$?
  assert_eq 1 "$rc" "exit code"
  assert_contains "NB_ROOT" "$out" "error names NB_ROOT"
}

test_alias_add_creates_entry() {
  export NB_PROJECT=TestApp NB_ROOT="$TEST_HOME/repo"
  nb add ft FeatureBranch >/dev/null 2>&1
  local content
  content="$(cat "$TEST_HOME/.nb_aliases" 2>/dev/null)"
  assert_contains $'ft\tFeatureBranch' "$content" "tab-separated entry written"
}

test_alias_add_replaces_existing_alias() {
  export NB_PROJECT=TestApp NB_ROOT="$TEST_HOME/repo"
  nb add ft First >/dev/null 2>&1
  nb add ft Second >/dev/null 2>&1
  local content
  content="$(cat "$TEST_HOME/.nb_aliases")"
  assert_contains $'ft\tSecond' "$content" "new value present"
  assert_not_contains "First" "$content" "old value removed"
}

test_alias_add_replaces_existing_worktree() {
  # Each worktree gets at most one alias; re-adding under a new alias should
  # remove the prior alias for the same worktree.
  export NB_PROJECT=TestApp NB_ROOT="$TEST_HOME/repo"
  nb add ft FeatureBranch >/dev/null 2>&1
  nb add f2 FeatureBranch >/dev/null 2>&1
  local content
  content="$(cat "$TEST_HOME/.nb_aliases")"
  assert_contains $'f2\tFeatureBranch' "$content" "new alias mapped"
  assert_not_contains $'ft\t' "$content" "old alias for same worktree removed"
}

test_alias_remove_existing() {
  export NB_PROJECT=TestApp NB_ROOT="$TEST_HOME/repo"
  nb add ft FeatureBranch >/dev/null 2>&1
  nb remove ft >/dev/null 2>&1
  local content
  content="$(cat "$TEST_HOME/.nb_aliases")"
  assert_not_contains "ft" "$content" "entry deleted"
}

test_alias_remove_unknown() {
  export NB_PROJECT=TestApp NB_ROOT="$TEST_HOME/repo"
  local out rc
  out="$(nb remove nonexistent 2>&1)"; rc=$?
  assert_eq 1 "$rc" "exit code"
  assert_contains "not found" "$out" "error message"
}

test_alias_add_wrong_arg_count() {
  export NB_PROJECT=TestApp NB_ROOT="$TEST_HOME/repo"
  local out rc
  out="$(nb add only-one 2>&1)"; rc=$?
  assert_eq 1 "$rc" "exit code"
  assert_contains "Usage" "$out" "usage shown"
}

test_run_current_needs_bundle_id() {
  export NB_PROJECT=TestApp NB_ROOT="$TEST_HOME/repo"
  local out rc
  out="$(nb run --current logs 2>&1)"; rc=$?
  assert_eq 1 "$rc" "exit code"
  assert_contains "NB_BUNDLE_ID" "$out" "names NB_BUNDLE_ID"
}

test_run_current_bad_sub_prints_usage() {
  export NB_PROJECT=TestApp NB_ROOT="$TEST_HOME/repo" NB_BUNDLE_ID=com.test.app
  local out rc
  out="$(nb run --current bogus 2>&1)"; rc=$?
  assert_eq 1 "$rc" "exit code"
  assert_contains "Usage" "$out" "usage shown"
}

test_run_current_empty_sub_prints_usage() {
  export NB_PROJECT=TestApp NB_ROOT="$TEST_HOME/repo" NB_BUNDLE_ID=com.test.app
  local out rc
  out="$(nb run --current 2>&1)"; rc=$?
  assert_eq 1 "$rc" "exit code"
  assert_contains "Usage" "$out" "usage shown"
}

test_run_physical_current_needs_device_id() {
  export NB_PROJECT=TestApp NB_ROOT="$TEST_HOME/repo" NB_BUNDLE_ID=com.test.app
  local out rc
  out="$(nb run physical --current stop 2>&1)"; rc=$?
  assert_eq 1 "$rc" "exit code"
  assert_contains "NB_PHYSICAL_DEVICE_ID" "$out" "names NB_PHYSICAL_DEVICE_ID"
}

test_run_physical_current_logs_prints_options() {
  export NB_PROJECT=TestApp NB_ROOT="$TEST_HOME/repo"
  export NB_BUNDLE_ID=com.test.app NB_PHYSICAL_DEVICE_ID=00000000-FAKE
  local out rc
  out="$(nb run physical --current logs 2>&1)"; rc=$?
  assert_eq 1 "$rc" "exit code (logs prints options + returns 1)"
  assert_contains "lldb" "$out" "mentions lldb workflow"
  assert_contains "Console.app" "$out" "mentions Console.app"
}

test_run_physical_current_record_unsupported() {
  export NB_PROJECT=TestApp NB_ROOT="$TEST_HOME/repo"
  export NB_BUNDLE_ID=com.test.app NB_PHYSICAL_DEVICE_ID=00000000-FAKE
  local out rc
  out="$(nb run physical --current record 2>&1)"; rc=$?
  assert_eq 1 "$rc" "exit code"
  assert_contains "QuickTime" "$out" "suggests QuickTime"
}

test_help_flag_prints_usage_without_env() {
  # --help should work even without NB_PROJECT/NB_ROOT set, and list the
  # main subcommands so users can discover them.
  local out rc
  out="$(nb --help 2>&1)"; rc=$?
  assert_eq 0 "$rc" "exit code"
  assert_contains "Usage:" "$out" "shows usage header"
  assert_contains "nb nav" "$out" "lists nav"
  assert_contains "nb open" "$out" "lists open"
  assert_contains "nb run" "$out" "lists run"
  assert_contains "nb add" "$out" "lists add"
  assert_contains "nb remove" "$out" "lists remove"
}

test_help_short_flag_prints_usage() {
  local out rc
  out="$(nb -h 2>&1)"; rc=$?
  assert_eq 0 "$rc" "exit code"
  assert_contains "Usage:" "$out" "shows usage header"
}

test_unknown_top_level_arg_treated_as_nav() {
  # `nb foo` with no foo worktree should fall through to nav and complain.
  # The function tries to resolve `foo` as a worktree; since NB_ROOT isn't a
  # git repo, we expect the "Not a git repo" error.
  export NB_PROJECT=TestApp NB_ROOT="$TEST_HOME/not-a-repo"
  local out rc
  out="$(nb foo 2>&1)"; rc=$?
  assert_eq 1 "$rc" "exit code"
  assert_contains "Not a git repo" "$out" "treated as nav, hits root check"
}

# ------------------------------- runner --------------------------------------

tests=(
  test_missing_project_errors
  test_missing_root_errors
  test_alias_add_creates_entry
  test_alias_add_replaces_existing_alias
  test_alias_add_replaces_existing_worktree
  test_alias_remove_existing
  test_alias_remove_unknown
  test_alias_add_wrong_arg_count
  test_run_current_needs_bundle_id
  test_run_current_bad_sub_prints_usage
  test_run_current_empty_sub_prints_usage
  test_run_physical_current_needs_device_id
  test_run_physical_current_logs_prints_options
  test_run_physical_current_record_unsupported
  test_help_flag_prints_usage_without_env
  test_help_short_flag_prints_usage
  test_unknown_top_level_arg_treated_as_nav
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
