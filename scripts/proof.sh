#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PASS_COUNT=0
FAIL_COUNT=0
GENERATED_DIR=""
LIVE_LABEL=""
LIVE_PLIST=""
LIVE_SCRIPT=""
LIVE_TASK_JSON=""
LIVE_MARKER=""
LIVE_LOG=""
LIVE_ERR_LOG=""

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL: %s\n' "$1"
}

run() {
  printf '\n+'
  printf ' %q' "$@"
  printf '\n'
  if "$@"; then
    pass "$*"
  else
    fail "$*"
  fi
}

remove_if_exists() {
  for path in "$@"; do
    if [ -e "$path" ]; then
      rm "$path"
    fi
  done
}

cleanup() {
  if [ -n "$LIVE_LABEL" ]; then
    launchctl bootout "gui/$(id -u)/$LIVE_LABEL" >/dev/null 2>&1 || true
  fi
  if [ -n "$LIVE_PLIST" ]; then
    launchctl bootout "gui/$(id -u)" "$LIVE_PLIST" >/dev/null 2>&1 || true
  fi
  remove_if_exists "$LIVE_PLIST" "$LIVE_SCRIPT" "$LIVE_TASK_JSON" "$LIVE_MARKER"
  if [ -n "$GENERATED_DIR" ] && [ -d "$GENERATED_DIR" ]; then
    find "$GENERATED_DIR" -type f -name '*.plist' -exec rm {} \;
    rmdir "$GENERATED_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT

no_placeholders() {
  local pattern
  pattern='TB''D|TO''DO|FIX''ME|\{\{[^}]+\}\}'
  ! rg -n --glob '!/.git/**' --glob '!/.build/**' --glob '!progress.tsv' \
    "$pattern" .
}

render_and_lint_fixtures() {
  GENERATED_DIR="$(mktemp -d "${TMPDIR:-/tmp}/launchdeck-proof.XXXXXX")"
  for fixture in Fixtures/managed-tasks/*.json; do
    local name
    name="$(basename "$fixture" .json)"
    .build/debug/launchdeck render-plist "$fixture" "$GENERATED_DIR/$name.plist" || return 1
    plutil -lint "$GENERATED_DIR/$name.plist" || return 1
  done
}

write_live_files() {
  local uid
  uid="$(id -u)"
  LIVE_LABEL="dev.seunan.launchdeck.proof.$(date +%Y%m%d%H%M%S).$$"
  local support_dir="$HOME/Library/Application Support/LaunchDeck/proof"
  local log_dir="$HOME/Library/Logs/LaunchDeck"

  mkdir -p "$HOME/Library/LaunchAgents" "$support_dir" "$log_dir"
  LIVE_PLIST="$HOME/Library/LaunchAgents/$LIVE_LABEL.plist"
  LIVE_SCRIPT="$support_dir/$LIVE_LABEL.sh"
  LIVE_TASK_JSON="$support_dir/$LIVE_LABEL.json"
  LIVE_MARKER="$support_dir/$LIVE_LABEL.marker"
  LIVE_LOG="$log_dir/$LIVE_LABEL.log"
  LIVE_ERR_LOG="$log_dir/$LIVE_LABEL.err.log"

  cat > "$LIVE_SCRIPT" <<EOF_SCRIPT
#!/bin/sh
marker="\$1"
log="\$2"
{
  echo "label=$LIVE_LABEL"
  echo "exit_status=0"
} >> "\$log"
echo "done" > "\$marker"
sleep 2
exit 0
EOF_SCRIPT
  chmod +x "$LIVE_SCRIPT"

  cat > "$LIVE_TASK_JSON" <<EOF_JSON
{
  "afterRunPolicy" : "cleanupPlist",
  "createdAt" : 1800000000,
  "environmentVariables" : {
    "PATH" : "/usr/bin:/bin"
  },
  "id" : "live-proof",
  "label" : "$LIVE_LABEL",
  "programArguments" : [
    "$LIVE_SCRIPT",
    "$LIVE_MARKER",
    "$LIVE_LOG"
  ],
  "schedule" : {
    "seconds" : 86400,
    "type" : "interval"
  },
  "standardErrorPath" : "$LIVE_ERR_LOG",
  "standardOutPath" : "$LIVE_LOG",
  "title" : "Live Proof",
  "updatedAt" : 1800000000,
  "workingDirectory" : "$support_dir"
}
EOF_JSON
}

wait_for_marker() {
  local i
  for i in $(seq 1 50); do
    if [ -f "$LIVE_MARKER" ]; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

live_launchd_check() {
  write_live_files || return 1
  .build/debug/launchdeck render-plist "$LIVE_TASK_JSON" "$LIVE_PLIST" || return 1
  plutil -lint "$LIVE_PLIST" || return 1
  launchctl bootstrap "gui/$(id -u)" "$LIVE_PLIST" || return 1
  launchctl kickstart -kp "gui/$(id -u)/$LIVE_LABEL" || return 1
  wait_for_marker || return 1
  local status_output
  status_output="$(.build/debug/launchdeck inspect "$LIVE_LABEL" "$LIVE_PLIST")" || return 1
  printf '%s\n' "$status_output"
  printf '%s\n' "$status_output" | grep -q 'plist_exists=true' || return 1
  printf '%s\n' "$status_output" | grep -q 'loaded=true' || return 1
  printf '%s\n' "$status_output" | grep -Eq 'running_pid=[0-9]+' || return 1
  printf '%s\n' "$status_output" | grep -Eq 'last_exit_status=[0-9]+' || return 1
  printf '%s\n' "$status_output" | grep -q 'disabled=false' || return 1
  local raw_output
  raw_output="$(.build/debug/launchdeck inspect-raw "$LIVE_LABEL" "$LIVE_PLIST")" || return 1
  printf '%s\n' "$raw_output" | grep -q "$LIVE_LABEL" || return 1
  launchctl bootout "gui/$(id -u)" "$LIVE_PLIST" || return 1
  grep -q 'exit_status=0' "$LIVE_LOG" || return 1
  remove_if_exists "$LIVE_PLIST" "$LIVE_SCRIPT" "$LIVE_TASK_JSON" "$LIVE_MARKER"
}

cleanup_verified() {
  [ ! -e "$LIVE_PLIST" ] &&
    [ ! -e "$LIVE_SCRIPT" ] &&
    [ ! -e "$LIVE_TASK_JSON" ] &&
    [ ! -e "$LIVE_MARKER" ] &&
    [ -f "$LIVE_LOG" ] &&
    grep -q 'exit_status=0' "$LIVE_LOG"
}

run swift build
run swift test
run no_placeholders
run render_and_lint_fixtures
run live_launchd_check
run cleanup_verified

printf '\nProof summary: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
