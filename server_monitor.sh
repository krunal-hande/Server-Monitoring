#!/usr/bin/env bash
# =============================================================================
# server_monitor.sh — Industry-Level Server Performance Monitor
# =============================================================================
# Description : Collects and displays real-time CPU, memory, disk usage,
#               and top processes. Supports JSON output, log rotation,
#               alerting thresholds, and continuous watch mode.
#
# Author      : ZORO
# Version     : 1.0.0
#
# Usage:
#   Automate and monitor  server activities and alerts while somethings goes wrong for eg. cpu usage, ram, memory 
#
# Options:
#   -i, --interval <sec>     Refresh interval in seconds (default: 5)
#   -o, --output <file>      Log output to file
#   -j, --json               Output in JSON format
#   -w, --watch              Run continuously (Ctrl+C to stop)
#   -n, --top-count <num>    Number of top processes to show (default: 5)
#   --cpu-alert <pct>        CPU alert threshold in % (default: 85)
#   --mem-alert <pct>        Memory alert threshold in % (default: 85)
#   --disk-alert <pct>       Disk alert threshold in % (default: 90)
#   -h, --help               Show this help message
#
# Examples:
#   ./server_monitor.sh
#   ./server_monitor.sh -w -i 3
#   ./server_monitor.sh -j -o /var/log/perf.json
#   ./server_monitor.sh --cpu-alert 75 --mem-alert 80 -w
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# CONSTANTS & DEFAULTS
# ---------------------------------------------------------------------------
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="1.0.0"
readonly TIMESTAMP="$(date '+%Y-%m-%dT%H:%M:%S%z')"
readonly HOSTNAME="$(hostname -f 2>/dev/null || hostname)"

INTERVAL=5
TOP_COUNT=5
WATCH_MODE=false
JSON_MODE=false
OUTPUT_FILE=""
CPU_ALERT_THRESHOLD=85
MEM_ALERT_THRESHOLD=85
DISK_ALERT_THRESHOLD=90

# ANSI color codes (disabled automatically when not a TTY)
if [[ -t 1 ]]; then
  RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'
  RESET='\033[0m'; UNDERLINE='\033[4m'
else
  RED=''; YELLOW=''; GREEN=''; CYAN=''; BOLD=''; DIM=''; RESET=''; UNDERLINE=''
fi

# ---------------------------------------------------------------------------
# LOGGING
# ---------------------------------------------------------------------------
log_info()  { echo -e "${CYAN}[INFO ]${RESET} $*" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN ]${RESET} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# ---------------------------------------------------------------------------
# USAGE / HELP
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
${BOLD}${SCRIPT_NAME} v${SCRIPT_VERSION}${RESET} — Real-Time Server Performance Monitor

${UNDERLINE}USAGE${RESET}
  $SCRIPT_NAME [OPTIONS]

${UNDERLINE}OPTIONS${RESET}
  -i, --interval <sec>     Refresh interval in seconds          (default: ${INTERVAL})
  -n, --top-count <num>    Top N processes to display           (default: ${TOP_COUNT})
  -o, --output <file>      Append metrics to a log file
  -j, --json               Emit metrics as JSON (one object/line)
  -w, --watch              Run continuously until Ctrl+C
      --cpu-alert  <pct>   Alert if CPU  usage exceeds this %   (default: ${CPU_ALERT_THRESHOLD})
      --mem-alert  <pct>   Alert if MEM  usage exceeds this %   (default: ${MEM_ALERT_THRESHOLD})
      --disk-alert <pct>   Alert if DISK usage exceeds this %   (default: ${DISK_ALERT_THRESHOLD})
  -h, --help               Show this help and exit

${UNDERLINE}EXAMPLES${RESET}
  $SCRIPT_NAME                          # Single snapshot
  $SCRIPT_NAME -w -i 3                  # Continuous, refresh every 3 s
  $SCRIPT_NAME -j -o /var/log/perf.log  # JSON output to log file
  $SCRIPT_NAME --cpu-alert 70 -w        # Alert when CPU > 70 %
EOF
}

# ---------------------------------------------------------------------------
# ARGUMENT PARSING
# ---------------------------------------------------------------------------
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -i|--interval)     INTERVAL="${2:?'--interval requires a value'}"; shift 2 ;;
      -n|--top-count)    TOP_COUNT="${2:?'--top-count requires a value'}"; shift 2 ;;
      -o|--output)       OUTPUT_FILE="${2:?'--output requires a file path'}"; shift 2 ;;
      -j|--json)         JSON_MODE=true; shift ;;
      -w|--watch)        WATCH_MODE=true; shift ;;
      --cpu-alert)       CPU_ALERT_THRESHOLD="${2:?'--cpu-alert requires a value'}"; shift 2 ;;
      --mem-alert)       MEM_ALERT_THRESHOLD="${2:?'--mem-alert requires a value'}"; shift 2 ;;
      --disk-alert)      DISK_ALERT_THRESHOLD="${2:?'--disk-alert requires a value'}"; shift 2 ;;
      -h|--help)         usage; exit 0 ;;
      *)                 log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
  done

  # Validate numeric inputs
  for var_name in INTERVAL TOP_COUNT CPU_ALERT_THRESHOLD MEM_ALERT_THRESHOLD DISK_ALERT_THRESHOLD; do
    val="${!var_name}"
    if ! [[ "$val" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      log_error "--${var_name,,} must be a positive number (got: '$val')"
      exit 1
    fi
  done
}

# ---------------------------------------------------------------------------
# DEPENDENCY CHECK
# ---------------------------------------------------------------------------
check_dependencies() {
  local missing=()
  for cmd in awk grep sed ps df free top; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required commands: ${missing[*]}"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# METRIC COLLECTION — CPU
# ---------------------------------------------------------------------------
get_cpu_usage() {
  # Works on Linux (reads /proc/stat for accuracy) with awk fallback
  if [[ -r /proc/stat ]]; then
    # Sample twice with a short sleep for accurate delta
    local s1 s2
    s1=$(awk '/^cpu / {print $2,$3,$4,$5,$6,$7,$8}' /proc/stat)
    sleep 0.5
    s2=$(awk '/^cpu / {print $2,$3,$4,$5,$6,$7,$8}' /proc/stat)

    awk -v s1="$s1" -v s2="$s2" 'BEGIN {
      split(s1, a); split(s2, b)
      idle1=a[4]; idle2=b[4]
      total1=0; total2=0
      for(i=1;i<=7;i++){total1+=a[i]; total2+=b[i]}
      dtotal = total2 - total1
      didle  = idle2  - idle1
      if (dtotal == 0) { printf "0.00"; exit }
      printf "%.2f", (1 - didle/dtotal) * 100
    }'
  else
    # macOS / fallback: use top
    top -bn1 2>/dev/null \
      | grep -E "^(%Cpu|Cpu)" \
      | awk '{print 100 - $8}' \
      | head -1 \
      || echo "0.00"
  fi
}

# ---------------------------------------------------------------------------
# METRIC COLLECTION — MEMORY
# ---------------------------------------------------------------------------
get_memory_stats() {
  # Outputs: total_kb used_kb free_kb used_pct
  if [[ -r /proc/meminfo ]]; then
    awk '
      /^MemTotal:/     { total=$2 }
      /^MemAvailable:/ { avail=$2 }
      END {
        used  = total - avail
        pct   = (total > 0) ? (used/total)*100 : 0
        printf "%d %d %d %.2f", total, used, avail, pct
      }
    ' /proc/meminfo
  else
    # macOS fallback via vm_stat + sysctl
    local total_bytes page_size free_pages
    page_size=$(pagesize 2>/dev/null || echo 4096)
    total_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    free_pages=$(vm_stat 2>/dev/null | awk '/^Pages free/ {gsub(/\./,"",$3); print $3}')
    awk -v t="$total_bytes" -v ps="$page_size" -v fp="${free_pages:-0}" 'BEGIN {
      total_kb = t/1024
      free_kb  = fp * ps / 1024
      used_kb  = total_kb - free_kb
      pct      = (total_kb > 0) ? (used_kb/total_kb)*100 : 0
      printf "%d %d %d %.2f", total_kb, used_kb, free_kb, pct
    }'
  fi
}

# ---------------------------------------------------------------------------
# METRIC COLLECTION — DISK
# ---------------------------------------------------------------------------
get_disk_stats() {
  # Outputs for each real filesystem: mount source total_kb used_kb avail_kb used_pct
  df -Pkl 2>/dev/null \
    | awk 'NR>1 && /^\// {
        gsub(/%/,"",$5)
        printf "%s %s %d %d %d %d\n", $6, $1, $2, $3, $4, $5
      }' \
    | sort -k6 -rn
}

# ---------------------------------------------------------------------------
# METRIC COLLECTION — TOP PROCESSES (CPU)
# ---------------------------------------------------------------------------
get_top_cpu_procs() {
  ps -eo pid,user,pcpu,pmem,comm \
     --sort=-pcpu \
     2>/dev/null \
    | awk -v n="$TOP_COUNT" 'NR>1 && NR<=n+1 {
        printf "%s %s %.2f %.2f %s\n", $1, $2, $3, $4, $5
      }' \
    || ps -eo pid,user,pcpu,pmem,comm 2>/dev/null \
      | sort -k3 -rn \
      | awk -v n="$TOP_COUNT" 'NR>1 && NR<=n+1 {
          printf "%s %s %.2f %.2f %s\n", $1, $2, $3, $4, $5
        }'
}

# ---------------------------------------------------------------------------
# METRIC COLLECTION — TOP PROCESSES (MEMORY)
# ---------------------------------------------------------------------------
get_top_mem_procs() {
  ps -eo pid,user,pcpu,pmem,comm \
     --sort=-pmem \
     2>/dev/null \
    | awk -v n="$TOP_COUNT" 'NR>1 && NR<=n+1 {
        printf "%s %s %.2f %.2f %s\n", $1, $2, $3, $4, $5
      }' \
    || ps -eo pid,user,pcpu,pmem,comm 2>/dev/null \
      | sort -k4 -rn \
      | awk -v n="$TOP_COUNT" 'NR>1 && NR<=n+1 {
          printf "%s %s %.2f %.2f %s\n", $1, $2, $3, $4, $5
        }'
}

# ---------------------------------------------------------------------------
# HELPER: human-readable bytes from KB
# ---------------------------------------------------------------------------
human_kb() {
  awk -v kb="$1" 'BEGIN {
    if      (kb >= 1073741824) printf "%.2f TiB", kb/1073741824
    else if (kb >= 1048576)    printf "%.2f GiB", kb/1048576
    else if (kb >= 1024)       printf "%.2f MiB", kb/1024
    else                       printf "%d KiB",   kb
  }'
}

# ---------------------------------------------------------------------------
# HELPER: colored percentage bar
# ---------------------------------------------------------------------------
pct_bar() {
  local pct="${1%.*}"          # integer part
  local width=20
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local color

  if   (( pct >= CPU_ALERT_THRESHOLD )); then color="$RED"
  elif (( pct >= 60 ));                   then color="$YELLOW"
  else                                         color="$GREEN"
  fi

  printf "${color}["
  printf '%0.s█' $(seq 1 "$filled")  2>/dev/null || printf "%${filled}s" | tr ' ' '█'
  printf '%0.s░' $(seq 1 "$empty")   2>/dev/null || printf "%${empty}s"  | tr ' ' '░'
  printf "] %3d%%${RESET}" "$pct"
}

# ---------------------------------------------------------------------------
# ALERT CHECKER
# ---------------------------------------------------------------------------
check_alert() {
  local label="$1" value="$2" threshold="$3"
  local int_val="${value%.*}"
  if (( int_val >= threshold )); then
    log_warn "ALERT ▶ ${label} usage is ${value}% (threshold: ${threshold}%)"
  fi
}

# ---------------------------------------------------------------------------
# OUTPUT — PRETTY (default)
# ---------------------------------------------------------------------------
print_pretty() {
  local cpu_pct mem_stats disk_stats
  cpu_pct="$(get_cpu_usage)"
  read -r mem_total_kb mem_used_kb mem_free_kb mem_pct < <(get_memory_stats)

  local ts; ts="$(date '+%Y-%m-%d %H:%M:%S')"
  local divider="${DIM}$(printf '─%.0s' {1..70})${RESET}"

  echo ""
  echo -e "${divider}"
  echo -e " ${BOLD}⚙  SERVER PERFORMANCE STATS${RESET}   ${DIM}${HOSTNAME}  │  ${ts}${RESET}"
  echo -e "${divider}"

  # ── CPU ──────────────────────────────────────────────────────────────────
  echo -e "\n ${BOLD}▸ CPU USAGE${RESET}"
  printf "   Total CPU   : %s  %s%%\n" "$(pct_bar "$cpu_pct")" "$cpu_pct"
  check_alert "CPU" "$cpu_pct" "$CPU_ALERT_THRESHOLD"

  # ── MEMORY ───────────────────────────────────────────────────────────────
  echo -e "\n ${BOLD}▸ MEMORY USAGE${RESET}"
  printf "   Used        : %s  %s / %s\n" \
    "$(pct_bar "$mem_pct")" \
    "$(human_kb "$mem_used_kb")" \
    "$(human_kb "$mem_total_kb")"
  printf "   Free        : %s\n" "$(human_kb "$mem_free_kb")"
  check_alert "Memory" "$mem_pct" "$MEM_ALERT_THRESHOLD"

  # ── DISK ─────────────────────────────────────────────────────────────────
  echo -e "\n ${BOLD}▸ DISK USAGE${RESET}"
  while IFS=' ' read -r mount source total_kb used_kb avail_kb used_pct; do
    printf "   %-12s: %s  %s / %s  (free: %s)\n" \
      "$mount" \
      "$(pct_bar "$used_pct")" \
      "$(human_kb "$used_kb")" \
      "$(human_kb "$total_kb")" \
      "$(human_kb "$avail_kb")"
    check_alert "Disk[$mount]" "$used_pct" "$DISK_ALERT_THRESHOLD"
  done < <(get_disk_stats)

  # ── TOP PROCESSES — CPU ───────────────────────────────────────────────────
  echo -e "\n ${BOLD}▸ TOP ${TOP_COUNT} PROCESSES BY CPU${RESET}"
  printf "   ${DIM}%-8s %-14s %8s %8s  %-s${RESET}\n" "PID" "USER" "CPU%" "MEM%" "COMMAND"
  while IFS=' ' read -r pid user cpu mem cmd; do
    printf "   %-8s %-14s %7.2f%% %7.2f%%  %-s\n" "$pid" "$user" "$cpu" "$mem" "$cmd"
  done < <(get_top_cpu_procs)

  # ── TOP PROCESSES — MEMORY ────────────────────────────────────────────────
  echo -e "\n ${BOLD}▸ TOP ${TOP_COUNT} PROCESSES BY MEMORY${RESET}"
  printf "   ${DIM}%-8s %-14s %8s %8s  %-s${RESET}\n" "PID" "USER" "CPU%" "MEM%" "COMMAND"
  while IFS=' ' read -r pid user cpu mem cmd; do
    printf "   %-8s %-14s %7.2f%% %7.2f%%  %-s\n" "$pid" "$user" "$cpu" "$mem" "$cmd"
  done < <(get_top_mem_procs)

  echo -e "\n${divider}\n"
}

# ---------------------------------------------------------------------------
# OUTPUT — JSON
# ---------------------------------------------------------------------------
print_json() {
  local cpu_pct
  cpu_pct="$(get_cpu_usage)"
  read -r mem_total_kb mem_used_kb mem_free_kb mem_pct < <(get_memory_stats)

  # Build disk JSON array
  local disk_json=""
  while IFS=' ' read -r mount source total_kb used_kb avail_kb used_pct; do
    [[ -n "$disk_json" ]] && disk_json+=","
    disk_json+="{\"mount\":\"${mount}\",\"device\":\"${source}\",\"total_kb\":${total_kb},\"used_kb\":${used_kb},\"free_kb\":${avail_kb},\"used_pct\":${used_pct}}"
    check_alert "Disk[$mount]" "$used_pct" "$DISK_ALERT_THRESHOLD"
  done < <(get_disk_stats)

  # Build CPU procs JSON array
  local cpu_procs=""
  while IFS=' ' read -r pid user cpu mem cmd; do
    [[ -n "$cpu_procs" ]] && cpu_procs+=","
    cpu_procs+="{\"pid\":${pid},\"user\":\"${user}\",\"cpu_pct\":${cpu},\"mem_pct\":${mem},\"command\":\"${cmd}\"}"
  done < <(get_top_cpu_procs)

  # Build MEM procs JSON array
  local mem_procs=""
  while IFS=' ' read -r pid user cpu mem cmd; do
    [[ -n "$mem_procs" ]] && mem_procs+=","
    mem_procs+="{\"pid\":${pid},\"user\":\"${user}\",\"cpu_pct\":${cpu},\"mem_pct\":${mem},\"command\":\"${cmd}\"}"
  done < <(get_top_mem_procs)

  check_alert "CPU"    "$cpu_pct"  "$CPU_ALERT_THRESHOLD"
  check_alert "Memory" "$mem_pct"  "$MEM_ALERT_THRESHOLD"

  local json
  json=$(cat <<EOF
{"timestamp":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')","hostname":"${HOSTNAME}","cpu":{"usage_pct":${cpu_pct},"alert_threshold":${CPU_ALERT_THRESHOLD}},"memory":{"total_kb":${mem_total_kb},"used_kb":${mem_used_kb},"free_kb":${mem_free_kb},"used_pct":${mem_pct},"alert_threshold":${MEM_ALERT_THRESHOLD}},"disk":[${disk_json}],"top_cpu_processes":[${cpu_procs}],"top_mem_processes":[${mem_procs}]}
EOF
)
  echo "$json"
}

# ---------------------------------------------------------------------------
# WRITE TO FILE (optional)
# ---------------------------------------------------------------------------
write_output() {
  local content="$1"
  if [[ -n "$OUTPUT_FILE" ]]; then
    echo "$content" >> "$OUTPUT_FILE"
  fi
}

# ---------------------------------------------------------------------------
# MAIN COLLECTION LOOP
# ---------------------------------------------------------------------------
run_once() {
  if $JSON_MODE; then
    local out; out="$(print_json)"
    echo "$out"
    write_output "$out"
  else
    # Capture once — render to terminal AND strip ANSI for the log file
    # from the same single collection run, avoiding double metric sampling.
    local out; out="$(print_pretty)"
    echo -e "$out"
    if [[ -n "$OUTPUT_FILE" ]]; then
      printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g' >> "$OUTPUT_FILE"
    fi
  fi
}

run_watch() {
  log_info "Starting continuous monitor on ${HOSTNAME} (interval: ${INTERVAL}s) — Ctrl+C to stop"
  # Hide cursor while watching
  tput civis 2>/dev/null || true
  trap 'tput cnorm 2>/dev/null || true; echo; log_info "Monitor stopped."; exit 0' INT TERM
  while true; do
    $JSON_MODE || clear
    run_once
    sleep "$INTERVAL"
  done
}

# ---------------------------------------------------------------------------
# ENTRY POINT
# ---------------------------------------------------------------------------
main() {
  parse_args "$@"
  check_dependencies

  if [[ -n "$OUTPUT_FILE" ]]; then
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    log_info "Logging to: ${OUTPUT_FILE}"
  fi

  if $WATCH_MODE; then
    run_watch
  else
    run_once
  fi
}

main "$@"
