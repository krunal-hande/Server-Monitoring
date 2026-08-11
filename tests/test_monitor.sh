#!/usr/bin/env bash
# =============================================================================
# test_monitor.sh — Smoke tests for server_monitor.sh
# =============================================================================
# Run standalone:   bash tests/test_monitor.sh
# Run with bats:    bats tests/test_monitor.sh
# =============================================================================

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/server_monitor.sh"
PASS=0; FAIL=0

# ---------------------------------------------------------------------------
# Minimal bats-compatible shim (no-op when run under real bats)
# ---------------------------------------------------------------------------
if ! command -v bats &>/dev/null; then
  @test() { local desc="$1"; shift; run_test "$desc" "$@"; }
  run()   { output=$("$@" 2>&1); status=$?; }
  run_test() {
    local desc="$1"; shift
    if "$@" &>/dev/null 2>&1; then
      echo "  ✓  $desc"; (( PASS++ ))
    else
      echo "  ✗  $desc"; (( FAIL++ ))
    fi
  }
fi

# ---------------------------------------------------------------------------
# TESTS
# ---------------------------------------------------------------------------

@test "script exists and is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "--help exits 0 and prints usage" {
  run bash "$SCRIPT" --help
  [[ $status -eq 0 ]]
  echo "$output" | grep -q "USAGE"
}

@test "unknown flag exits non-zero" {
  run bash "$SCRIPT" --not-a-real-flag
  [[ $status -ne 0 ]]
}

@test "non-numeric interval is rejected" {
  run bash "$SCRIPT" --interval abc
  [[ $status -ne 0 ]]
}

@test "single snapshot exits 0" {
  run bash "$SCRIPT"
  [[ $status -eq 0 ]]
}

@test "single snapshot output contains CPU USAGE" {
  run bash "$SCRIPT"
  echo "$output" | grep -qi "CPU"
}

@test "single snapshot output contains MEMORY" {
  run bash "$SCRIPT"
  echo "$output" | grep -qi "MEMORY"
}

@test "single snapshot output contains DISK" {
  run bash "$SCRIPT"
  echo "$output" | grep -qi "DISK"
}

@test "json mode emits valid JSON" {
  run bash "$SCRIPT" -j
  [[ $status -eq 0 ]]
  echo "$output" | python3 -m json.tool > /dev/null 2>&1
}

@test "json output contains timestamp field" {
  run bash "$SCRIPT" -j
  echo "$output" | grep -q '"timestamp"'
}

@test "json output contains hostname field" {
  run bash "$SCRIPT" -j
  echo "$output" | grep -q '"hostname"'
}

@test "json output contains cpu.usage_pct" {
  run bash "$SCRIPT" -j
  echo "$output" | grep -q '"usage_pct"'
}

@test "json output contains disk array" {
  run bash "$SCRIPT" -j
  echo "$output" | grep -q '"disk"'
}

@test "json output contains top_cpu_processes" {
  run bash "$SCRIPT" -j
  echo "$output" | grep -q '"top_cpu_processes"'
}

@test "json output contains top_mem_processes" {
  run bash "$SCRIPT" -j
  echo "$output" | grep -q '"top_mem_processes"'
}

@test "--top-count 3 shows 3 cpu processes in json" {
  run bash "$SCRIPT" -j -n 3
  count=$(echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d['top_cpu_processes']))" 2>/dev/null)
  [[ "$count" -le 3 ]]
}

@test "output file is created when -o is passed" {
  tmpfile=$(mktemp)
  bash "$SCRIPT" -j -o "$tmpfile" > /dev/null 2>&1
  local rc=$?
  [[ -s "$tmpfile" ]]
  rm -f "$tmpfile"
  return $rc
}

@test "output file log is ANSI-clean in pretty mode" {
  tmpfile=$(mktemp)
  bash "$SCRIPT" -o "$tmpfile" > /dev/null 2>&1
  # Should contain no ESC characters
  ! grep -qP '\x1b' "$tmpfile"
  rm -f "$tmpfile"
}

# ---------------------------------------------------------------------------
# SUMMARY (standalone mode only)
# ---------------------------------------------------------------------------
if ! command -v bats &>/dev/null; then
  total=$(( PASS + FAIL ))
  echo ""
  echo "Results: ${PASS}/${total} passed"
  [[ $FAIL -eq 0 ]] && exit 0 || exit 1
fi
