# JSON Output Schema

When running with `-j` / `--json`, each line is a self-contained JSON object.

---

## Top-Level Fields

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | string (ISO 8601 UTC) | Collection time, e.g. `"2026-03-27T10:15:00Z"` |
| `hostname` | string | FQDN of the host (`hostname -f`) |
| `cpu` | object | CPU metrics — see below |
| `memory` | object | Memory metrics — see below |
| `disk` | array | One object per mounted filesystem |
| `top_cpu_processes` | array | Top N processes sorted by CPU% |
| `top_mem_processes` | array | Top N processes sorted by MEM% |

---

## `cpu` Object

| Field | Type | Description |
|-------|------|-------------|
| `usage_pct` | float | Aggregate CPU usage across all cores, 0–100 |
| `alert_threshold` | int | Configured alert threshold |

---

## `memory` Object

| Field | Type | Description |
|-------|------|-------------|
| `total_kb` | int | Total physical RAM in KB |
| `used_kb` | int | Used RAM (total − MemAvailable) in KB |
| `free_kb` | int | Available RAM (`MemAvailable`) in KB |
| `used_pct` | float | Used RAM as % of total |
| `alert_threshold` | int | Configured alert threshold |

---

## `disk[]` Object

| Field | Type | Description |
|-------|------|-------------|
| `mount` | string | Mount point, e.g. `"/"`, `"/var"` |
| `device` | string | Block device, e.g. `"/dev/sda1"` |
| `total_kb` | int | Total size of filesystem in KB |
| `used_kb` | int | Used space in KB |
| `free_kb` | int | Available space in KB |
| `used_pct` | int | Used space as % of total |

---

## `top_cpu_processes[]` / `top_mem_processes[]` Object

| Field | Type | Description |
|-------|------|-------------|
| `pid` | int | Process ID |
| `user` | string | Owning user |
| `cpu_pct` | float | CPU usage % |
| `mem_pct` | float | Memory usage % of total RAM |
| `command` | string | Process name (`comm`) |

---

## Full Example

```json
{
  "timestamp": "2026-03-27T10:15:00Z",
  "hostname": "prod-server-01",
  "cpu": {
    "usage_pct": 42.15,
    "alert_threshold": 85
  },
  "memory": {
    "total_kb": 16384000,
    "used_kb": 9830400,
    "free_kb": 6553600,
    "used_pct": 60.00,
    "alert_threshold": 85
  },
  "disk": [
    {
      "mount": "/",
      "device": "/dev/sda1",
      "total_kb": 512000000,
      "used_kb": 215040000,
      "free_kb": 296960000,
      "used_pct": 42
    },
    {
      "mount": "/var",
      "device": "/dev/sda2",
      "total_kb": 204800000,
      "used_kb": 147456000,
      "free_kb": 57344000,
      "used_pct": 72
    }
  ],
  "top_cpu_processes": [
    { "pid": 12451, "user": "app",      "cpu_pct": 11.80, "mem_pct": 4.20,  "command": "node"     },
    { "pid": 18892, "user": "mlops",    "cpu_pct":  9.40, "mem_pct": 12.10, "command": "python3"  },
    { "pid":  9823, "user": "postgres", "cpu_pct":  5.20, "mem_pct": 8.60,  "command": "postgres" },
    { "pid":  1023, "user": "www-data", "cpu_pct":  3.10, "mem_pct": 2.30,  "command": "nginx"    },
    { "pid":  7741, "user": "redis",    "cpu_pct":  1.80, "mem_pct": 3.50,  "command": "redis-server" }
  ],
  "top_mem_processes": [
    { "pid": 18892, "user": "mlops",    "cpu_pct":  9.40, "mem_pct": 12.10, "command": "python3"  },
    { "pid":  9823, "user": "postgres", "cpu_pct":  5.20, "mem_pct": 8.60,  "command": "postgres" },
    { "pid":  7741, "user": "redis",    "cpu_pct":  1.80, "mem_pct": 3.50,  "command": "redis-server" },
    { "pid": 12451, "user": "app",      "cpu_pct": 11.80, "mem_pct": 4.20,  "command": "node"     },
    { "pid":  1023, "user": "www-data", "cpu_pct":  3.10, "mem_pct": 2.30,  "command": "nginx"    }
  ]
}
```

---

## Parsing with `jq`

```bash
# Live CPU usage
./scripts/server_monitor.sh -w -j | jq '.cpu.usage_pct'

# Alert if any disk over 80%
./scripts/server_monitor.sh -j | jq '.disk[] | select(.used_pct > 80) | .mount'

# Top process names by memory
./scripts/server_monitor.sh -j | jq '[.top_mem_processes[].command]'

# Save pretty-printed snapshot
./scripts/server_monitor.sh -j | jq '.' > snapshot.json
```
