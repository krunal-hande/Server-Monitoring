# 📊 Server Performance Stats

A lightweight, dependency-free Bash tool for real-time Linux/macOS server monitoring — CPU, memory, disk, and top processes. Designed for DevOps teams, sysadmins, and CI pipelines.

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Shell](https://img.shields.io/badge/shell-bash%205%2B-green)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey)
![License](https://img.shields.io/badge/license-MIT-orange)

---

## ✨ Features

- **CPU usage** — delta-sampled from `/proc/stat` for accuracy (not just a `top` snapshot)
- **Memory** — uses `MemAvailable` (the correct production metric), shows used / free / total + swap
- **Disk** — all real filesystems, sorted by usage, with free/used/total breakdown
- **Top N processes** — by CPU and by memory, configurable count
- **JSON output** — one structured object per line, ready for log shippers (Filebeat, Fluentd, etc.)
- **Alert thresholds** — emits `[WARN]` lines when CPU / MEM / DISK exceed configured limits
- **Watch mode** — continuous refresh at any interval
- **Log file** — ANSI-stripped plain-text or JSON appended to any path
- **Cross-platform** — Linux (`/proc/stat`, `/proc/meminfo`) and macOS (`vm_stat`, `sysctl`) supported

---

## 📁 Project Structure

```
server-performance-stats/
├── scripts/
│   └── server_monitor.sh        # Main monitoring script
├── config/
│   └── monitor.conf             # Default thresholds & settings
├── logs/                        # Runtime log output (gitignored)
│   └── .gitkeep
├── docs/
│   ├── USAGE.md                 # Detailed CLI reference
│   └── JSON_SCHEMA.md           # JSON output field reference
├── tests/
│   └── test_monitor.sh          # Basic smoke tests (bats-compatible)
├── .github/
│   └── workflows/
│       └── ci.yml               # GitHub Actions: lint + smoke test
├── .gitignore
├── LICENSE
└── README.md
```

---

## 🚀 Quick Start

```bash
# Clone
git clone https://github.com/your-org/server-performance-stats.git
cd server-performance-stats

# Make executable
chmod +x scripts/server_monitor.sh

# Single snapshot
./scripts/server_monitor.sh

# Live watch, refresh every 3 s
./scripts/server_monitor.sh -w -i 3

# JSON stream to log file
./scripts/server_monitor.sh -w -j -o logs/perf.json

# Custom alert thresholds
./scripts/server_monitor.sh -w --cpu-alert 75 --mem-alert 80 --disk-alert 85
```

---

## ⚙️ Options

| Flag | Long form | Default | Description |
|------|-----------|---------|-------------|
| `-i` | `--interval` | `5` | Refresh interval in seconds |
| `-n` | `--top-count` | `5` | Number of top processes to show |
| `-o` | `--output` | _(none)_ | Append output to this log file |
| `-j` | `--json` | `false` | Emit one JSON object per line |
| `-w` | `--watch` | `false` | Run continuously (Ctrl+C to stop) |
| | `--cpu-alert` | `85` | Alert threshold for CPU % |
| | `--mem-alert` | `85` | Alert threshold for memory % |
| | `--disk-alert` | `90` | Alert threshold for disk % |
| `-h` | `--help` | | Show help and exit |

---

## 📦 JSON Output Sample

```json
{
  "timestamp": "2026-03-27T10:15:00Z",
  "hostname": "prod-server-01",
  "cpu": { "usage_pct": 42.15, "alert_threshold": 85 },
  "memory": {
    "total_kb": 16384000, "used_kb": 9830400,
    "free_kb": 6553600,   "used_pct": 60.00,
    "alert_threshold": 85
  },
  "disk": [
    { "mount": "/", "device": "/dev/sda1", "total_kb": 512000000,
      "used_kb": 215040000, "free_kb": 296960000, "used_pct": 42 }
  ],
  "top_cpu_processes": [
    { "pid": 12451, "user": "app", "cpu_pct": 11.80, "mem_pct": 4.20, "command": "node" }
  ],
  "top_mem_processes": [
    { "pid": 9823, "user": "postgres", "cpu_pct": 2.10, "mem_pct": 12.40, "command": "postgres" }
  ]
}
```

---

## 🔧 Configuration File

Default settings can be stored in `config/monitor.conf` and sourced automatically:

```bash
# config/monitor.conf
INTERVAL=5
TOP_COUNT=5
CPU_ALERT_THRESHOLD=85
MEM_ALERT_THRESHOLD=85
DISK_ALERT_THRESHOLD=90
OUTPUT_FILE="/var/log/server_perf.json"
JSON_MODE=true
```

---

## 🕐 Cron / Systemd Integration

**Cron** — snapshot every minute to JSON log:
```cron
* * * * * /opt/server-performance-stats/scripts/server_monitor.sh -j -o /var/log/perf.json
```

**Systemd service** — continuous watch mode as a service:
```ini
# /etc/systemd/system/server-monitor.service
[Unit]
Description=Server Performance Monitor
After=network.target

[Service]
ExecStart=/opt/server-performance-stats/scripts/server_monitor.sh -w -i 5 -j -o /var/log/perf.json
Restart=on-failure
User=nobody

[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable --now server-monitor
```

---

## 🧪 Running Tests

```bash
chmod +x tests/test_monitor.sh
bash tests/test_monitor.sh
```

Requires [bats-core](https://github.com/bats-core/bats-core) for structured test output:
```bash
bats tests/test_monitor.sh
```

---

## 📄 License

MIT — see [LICENSE](LICENSE)
