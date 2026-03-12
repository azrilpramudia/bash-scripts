# sysinfo.sh documentation

A lightweight, dependency-free system information script written in pure Bash and `awk`. Displays a clean snapshot of your system — OS, CPU, temperature, memory, disk — in a single terminal run. No colors, no bloat.

```
--------------------------------------------
         SYSTEM INFORMATION
--------------------------------------------
OS             : Linux Mint 22.3
Kernel         : 6.17.0-14-generic
Hostname       : meow
Uptime         : 1 hour, 31 minutes
Users Login    : 1
IP Address     : 192.168.0.100
--------------------------------------------
CPU Model      : Intel(R) Core(TM) i5-5200U CPU @ 2.20GHz
Cores          : 2
Threads        : 4
Load Avg       : 0.25 / 0.36 / 0.22 (1m/5m/15m)
CPU Temp       : 57.0°C
GPU Temp       : 49.0°C (Intel iGPU/PCH)
--------------------------------------------
RAM            : 3625/15871 MB (22.8%)
Swap           : No swap
Disk (/)       : 64G/197G (35%)
--------------------------------------------
Time           : 2026-03-13 08:00:00
--------------------------------------------
```

---

## Requirements

| Tool | Source | Notes |
|------|--------|-------|
| `bash` | Shell | Version 4.0+ |
| `awk` | gawk / mawk | Pre-installed on most distros |
| `free` | procps-ng | Linux only |
| `df`, `ps`, `uname` | coreutils | Available everywhere |
| `hostname`, `who` | inetutils / util-linux | Pre-installed on most distros |
| `/proc/cpuinfo` | Linux kernel | Linux only |
| `/proc/loadavg` | Linux kernel | Linux only |
| `/sys/class/hwmon` | Linux kernel sysfs | For temperature reading |

No external packages required for basic usage. Temperature detection uses only built-in kernel interfaces (`/sys/class/hwmon`, `/sys/class/thermal`).

---

## Installation

```bash
# Clone the repo
git clone https://github.com/yourusername/sysinfo.git
cd sysinfo

# Make executable
chmod +x sysinfo.sh

# Run
./sysinfo.sh
```

Optionally, move it to your PATH for global access:

```bash
sudo cp sysinfo.sh /usr/local/bin/sysinfo
sysinfo
```

---

## What It Shows

| Field | Source | Description |
|-------|--------|-------------|
| OS | `/etc/os-release` | Pretty name of the distro |
| Kernel | `uname -r` | Running kernel version |
| Hostname | `hostname` | Machine hostname |
| Uptime | `uptime -p` | Human-readable uptime |
| Users Login | `who` | Number of logged-in users |
| IP Address | `hostname -I` | Primary network interface IP |
| CPU Model | `/proc/cpuinfo` | Processor model name |
| Cores | `/proc/cpuinfo` | Physical core count |
| Threads | `/proc/cpuinfo` | Logical CPU count (vCPU) |
| Load Avg | `/proc/loadavg` | 1m / 5m / 15m load average |
| CPU Temp | `/sys/class/thermal` or `/sys/class/hwmon` | CPU die temperature |
| GPU Temp | `/sys/class/hwmon` or vendor tools | GPU temperature (see below) |
| RAM | `free -m` | Used / total memory with percentage |
| Swap | `free -m` | Used / total swap with percentage |
| Disk (/) | `df -h` | Root partition usage |
| Time | `date` | Timestamp of the run |

---

## GPU Temperature Detection

The script tries the following methods in order, stopping at the first successful result:

| # | Method | Target Hardware |
|---|--------|----------------|
| 1 | `nvidia-smi` | NVIDIA dedicated GPU |
| 2 | `rocm-smi` | AMD dedicated GPU |
| 3 | hwmon `nouveau` | NVIDIA via open-source driver |
| 4 | hwmon `amdgpu` / `radeon` | AMD dedicated & iGPU (reads `edge` label) |
| 5 | hwmon `i915` | Intel iGPU — gen 6 to gen 12 |
| 6 | hwmon `xe` | Intel Arc & gen 12.5+ (Meteor Lake) |
| 7 | hwmon `pch_*` | Intel iGPU on Broadwell/Haswell/Skylake (reads PCH sensor) |
| 8 | hwmon `thinkpad` | ThinkPad EC — reads explicit `GPU` label |
| 9 | hwmon `k10temp` | AMD APU — reads `Tccd` / `Tdie` label |
| 10 | hwmon `vc4` / `v3d` | Raspberry Pi GPU |
| 11 | `thermal_zone` type `gpu*` / `soc*` | ARM / embedded boards |
| 12 | `intel_gpu_top` | Intel iGPU last resort (requires `intel-gpu-tools`) |

If GPU temperature still shows `N/A`, your kernel may not expose a sensor for that GPU. This is common on older Intel iGPU (pre-Broadwell) and WSL2 environments.

> **Note for Intel iGPU/PCH:** On Intel 5th gen (Broadwell) laptops such as ThinkPads, temperature is read from the Platform Controller Hub (`pch_wildcat_point`) since the iGPU does not have its own hwmon node.

---

## Compatibility

| Distro / Environment | Status | Notes |
|----------------------|--------|-------|
| Ubuntu / Debian / Linux Mint | ✅ Full support | All tools available by default |
| RHEL / CentOS / AlmaLinux / Rocky | ✅ Full support | All tools available by default |
| Arch / Manjaro / EndeavourOS | ✅ Full support | `util-linux` included by default |
| Fedora / openSUSE | ✅ Full support | All tools available by default |
| Raspberry Pi OS | ✅ Full support | GPU temp via `vc4`/`v3d` driver |
| Alpine Linux | ⚠️ Partial | BusyBox `free`/`df` output differs; `uptime -p` missing; install `util-linux` |
| Android (Termux) | ⚠️ Partial | Most features work; `hostname -I` and `who` may need `pkg install` |
| Windows WSL2 | ⚠️ Partial | System info works; CPU/GPU temp always `N/A` (no `/sys/class/thermal`) |
| macOS | ❌ Not compatible | No `/proc`, no `free`, no `lscpu` — use `sysctl`/`vm_stat` instead |
| FreeBSD / OpenBSD | ❌ Not compatible | No `/proc` filesystem; different tool names and paths |

---

## Optional: lm-sensors for Better CPU/GPU Temperature

For more accurate temperature readings on Intel and AMD hardware, install `lm-sensors`:

```bash
# Ubuntu / Debian / Mint
sudo apt install lm-sensors
sudo sensors-detect

# Arch / Manjaro
sudo pacman -S lm_sensors
sudo sensors-detect

# Fedora
sudo dnf install lm_sensors
sudo sensors-detect

# RHEL / CentOS
sudo yum install lm_sensors
sudo sensors-detect
```

The script does not call `sensors` directly, but `sensors-detect` loads the correct kernel modules which then expose sensor nodes under `/sys/class/hwmon` — which the script reads.

---

## License

MIT License — free to use, modify, and distribute.
