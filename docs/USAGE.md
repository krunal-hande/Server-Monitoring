# Usage Reference

## Synopsis

```
server_monitor.sh [OPTIONS]
```

---

## All Options

| Flag | Long form | Type | Default | Description |
|------|-----------|------|---------|-------------|
| `-i` | `--interval` | int | `5` | Seconds between refreshes in watch mode |
| `-n` | `--top-count` | int | `5` | Top N processes to display |
| `-o` | `--output` | path | _(none)_ | File path to append log output |
| `-j` | `--json` | bool | `false` | Output as JSON (one object per line) |
| `-w` | `--watch` | bool | `false` | Run continuously until Ctrl+C |
| | `--cpu-alert` | int | `85` | CPU alert threshold % |
| | `--mem-alert` | int | `85` | Memory alert threshold % |
| | `--disk-alert` | int | `90` | Disk alert threshold % |
| `-h` | `--help` | | | Print help and exit |

---

## Examples

### Single snapshot (default pretty output)
```bash
./scripts/server_monitor.sh
```

### Continuous watch, 3-second refresh
```bash
./scripts/server_monitor.sh -w -i 3
```

### Show top 10 processes
```bash
./scripts/server_monitor.sh -n 10
```

### JSON output to stdout
```bash
./scripts/server_monitor.sh -j
```

### JSON stream to log file, watch mode
```bash
./scripts/server_monitor.sh -w -j -o /var/log/perf.json
```

### Custom alert thresholds
```bash
./scripts/server_monitor.sh -w --cpu-alert 70 --mem-alert 75 --disk-alert 80
```

### Pipe JSON into jq for live filtering
```bash
./scripts/server_monitor.sh -w -j | jq '.cpu.usage_pct'
```

### Grep alerts only from log
```bash
./scripts/server_monitor.sh -w 2>&1 | grep '\[WARN\]'
```

---

## Alert Output

When a threshold is exceeded, a warning is emitted to **stderr**:

```
[WARN ] ALERT ▶ CPU usage is 91.20% (threshold: 85%)
[WARN ] ALERT ▶ Disk[/var] usage is 93% (threshold: 90%)
```

These can be captured separately from normal output:
```bash
./scripts/server_monitor.sh -w 2>alerts.log
```

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Invalid argument or missing dependency |

---

## Configuration File

The script sources `config/monitor.conf` (relative to script location) or `/etc/server-monitor/monitor.conf` if present. CLI flags always take precedence over config file values.

```bash
# Minimal config example
INTERVAL=10
JSON_MODE=true
OUTPUT_FILE="/var/log/perf.json"
CPU_ALERT_THRESHOLD=80
```
