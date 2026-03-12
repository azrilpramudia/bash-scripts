#!/bin/bash

# --- System ---
os=$(awk -F'"' '/PRETTY_NAME/{print $2}' /etc/os-release 2>/dev/null)
kernel=$(uname -r)
hostname=$(hostname)
uptime=$(uptime -p | sed 's/up //')
users=$(who | wc -l | awk '{print $1}')
ip=$(hostname -I | awk '{print $1}')

# --- CPU ---
cpu_model=$(awk -F': ' '/model name/{print $2; exit}' /proc/cpuinfo)
cores=$(awk '/^core id/{c[$2]=1} END{print length(c)}' /proc/cpuinfo)
threads=$(awk '/^processor/{n++} END{print n}' /proc/cpuinfo)
load=$(awk '{print $1" / "$2" / "$3}' /proc/loadavg)

# --- Suhu CPU ---
cpu_temp="Tidak tersedia"
for zone in /sys/class/thermal/thermal_zone*/temp; do
    type=$(cat "${zone%temp}type" 2>/dev/null)
    case "$type" in
        x86_pkg_temp|coretemp|cpu-thermal|acpitz)
            raw=$(cat "$zone" 2>/dev/null)
            cpu_temp=$(awk "BEGIN{printf \"%.1f\", $raw/1000}")°C
            break
            ;;
    esac
done

# Fallback: hwmon coretemp
if [ "$cpu_temp" = "Tidak tersedia" ]; then
    for hwmon in /sys/class/hwmon/hwmon*/; do
        name=$(cat "${hwmon}name" 2>/dev/null | tr -d '[:space:]')
        if [ "$name" = "coretemp" ] && [ -r "${hwmon}temp1_input" ]; then
            raw=$(cat "${hwmon}temp1_input")
            cpu_temp=$(awk "BEGIN{printf \"%.1f\", $raw/1000}")°C
            break
        fi
    done
fi

# --- Suhu GPU ---
# Fungsi: baca millidegree dari file dan konversi ke °C
_read_temp() {
    local file="$1"
    local raw
    raw=$(cat "$file" 2>/dev/null | tr -d '[:space:]')
    [ -n "$raw" ] && [ "$raw" -gt 1000 ] 2>/dev/null && \
        awk "BEGIN{printf \"%.1f\", $raw/1000}"
}

gpu_temp="Tidak tersedia"

# [1] NVIDIA dedicated — nvidia-smi
if command -v nvidia-smi &>/dev/null; then
    _t=$(nvidia-smi --query-gpu=temperature.gpu \
         --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d '[:space:]')
    [ -n "$_t" ] && [ "$_t" -eq "$_t" ] 2>/dev/null && \
        gpu_temp="${_t}°C (NVIDIA)"
fi

# [2] AMD dedicated — rocm-smi
if [ "$gpu_temp" = "Tidak tersedia" ] && command -v rocm-smi &>/dev/null; then
    _t=$(rocm-smi --showtemp 2>/dev/null | \
         awk '/Temperature/{gsub(/[^0-9.]/,"",$NF); print $NF; exit}')
    [ -n "$_t" ] && gpu_temp="${_t}°C (AMD Dedicated)"
fi

# [3] Scan seluruh hwmon — cek nama driver satu per satu
if [ "$gpu_temp" = "Tidak tersedia" ]; then
    for hwmon in /sys/class/hwmon/hwmon*/; do
        [ -d "$hwmon" ] || continue
        drv=$(cat "${hwmon}name" 2>/dev/null | tr -d '[:space:]')

        case "$drv" in

            # --- NVIDIA via hwmon (driver nouveau/open kernel) ---
            nouveau)
                _t=$(_read_temp "${hwmon}temp1_input")
                [ -n "$_t" ] && gpu_temp="${_t}°C (NVIDIA/nouveau)" && break
                ;;

            # --- AMD dedicated & iGPU (amdgpu/radeon) ---
            amdgpu|radeon)
                # Cari label 'edge' dulu (suhu die), fallback ke temp1
                _t=""
                for tf in "${hwmon}"temp*_input; do
                    [ -r "$tf" ] || continue
                    lbl=$(cat "${tf%_input}_label" 2>/dev/null | tr -d '[:space:]')
                    if [ "$lbl" = "edge" ] || [ "$lbl" = "junction" ]; then
                        _t=$(_read_temp "$tf") && break
                    fi
                done
                [ -z "$_t" ] && _t=$(_read_temp "${hwmon}temp1_input")
                [ -n "$_t" ] && gpu_temp="${_t}°C (AMD GPU)" && break
                ;;

            # --- Intel iGPU generasi baru (driver i915 / xe) ---
            i915)
                _t=$(_read_temp "${hwmon}temp1_input")
                [ -n "$_t" ] && gpu_temp="${_t}°C (Intel iGPU/i915)" && break
                ;;
            xe)
                _t=$(_read_temp "${hwmon}temp1_input")
                [ -n "$_t" ] && gpu_temp="${_t}°C (Intel Arc/xe)" && break
                ;;

            # --- Intel PCH (Broadwell/Haswell/Skylake dst) ---
            # pch_wildcat_point, pch_sunrise_point, pch_cannonlake, dll
            pch_*|pch)
                _t=$(_read_temp "${hwmon}temp1_input")
                [ -n "$_t" ] && gpu_temp="${_t}°C (Intel iGPU/PCH)" && break
                ;;

            # --- ThinkPad EC — cari label GPU eksplisit ---
            thinkpad)
                for tf in "${hwmon}"temp*_input; do
                    [ -r "$tf" ] || continue
                    lbl=$(cat "${tf%_input}_label" 2>/dev/null | tr -d '[:space:]')
                    if [ "$lbl" = "GPU" ]; then
                        _t=$(_read_temp "$tf")
                        [ -n "$_t" ] && gpu_temp="${_t}°C (Intel iGPU/ThinkPad)" && break 2
                    fi
                done
                ;;

            # --- AMD APU — k10temp, cari label Tccd/Tdie ---
            k10temp)
                for tf in "${hwmon}"temp*_input; do
                    [ -r "$tf" ] || continue
                    lbl=$(cat "${tf%_input}_label" 2>/dev/null | tr -d '[:space:]')
                    case "$lbl" in
                        Tccd*|Tdie*)
                            _t=$(_read_temp "$tf")
                            [ -n "$_t" ] && gpu_temp="${_t}°C (AMD APU)" && break 2
                            ;;
                    esac
                done
                ;;

            # --- Raspberry Pi / ARM iGPU (vc4, v3d) ---
            vc4|v3d)
                _t=$(_read_temp "${hwmon}temp1_input")
                [ -n "$_t" ] && gpu_temp="${_t}°C (RPi GPU)" && break
                ;;

        esac
    done
fi

# [4] Fallback thermal_zone — cari tipe GPU/DISP
if [ "$gpu_temp" = "Tidak tersedia" ]; then
    for zone in /sys/class/thermal/thermal_zone*/temp; do
        type=$(cat "${zone%temp}type" 2>/dev/null | tr -d '[:space:]')
        case "$type" in
            gpu*|GPU*|disp*|DISP*|soc*|SOC*)
                raw=$(cat "$zone" 2>/dev/null | tr -d '[:space:]')
                if [ -n "$raw" ] && [ "$raw" -gt 1000 ] 2>/dev/null; then
                    gpu_temp=$(awk "BEGIN{printf \"%.1f\", $raw/1000}")°C
                    gpu_temp="${gpu_temp} (${type})"
                    break
                fi
                ;;
        esac
    done
fi

# [5] Last resort: intel_gpu_top (butuh package intel-gpu-tools)
if [ "$gpu_temp" = "Tidak tersedia" ] && command -v intel_gpu_top &>/dev/null; then
    _t=$(timeout 2 intel_gpu_top -J -s 1 2>/dev/null | \
         awk -F: '/"temperature"/{gsub(/[^0-9.]/,"",$2); if($2!="") print $2; exit}')
    [ -n "$_t" ] && gpu_temp="${_t}°C (Intel iGPU/gpu_top)"
fi

# --- Memory ---
ram=$(free -m | awk 'NR==2{printf "%d/%d MB (%.1f%%)", $3, $2, $3*100/$2}')
swap=$(free -m | awk 'NR==3{
    if ($2 > 0) printf "%d/%d MB (%.1f%%)", $3, $2, $3*100/$2
    else print "Tidak ada swap"
}')

# --- Disk ---
disk=$(df -h | awk '$NF=="/"{printf "%s/%s (%s)", $3, $2, $5}')

# --- Proses ---
total_proc=$(ps aux --no-header | wc -l)
run_proc=$(ps aux --no-header | awk '$8~/^R/{n++} END{print n+0}')

# ================================
#  Output
# ================================

awk 'BEGIN{
    W = 44
    sep = ""
    for (i=1; i<=W; i++) sep = sep "-"
    print sep
    print "         SYSTEM MONITOR"
    print sep
}'

printf "%-14s : %s\n" "OS"           "$os"
printf "%-14s : %s\n" "Kernel"       "$kernel"
printf "%-14s : %s\n" "Hostname"     "$hostname"
printf "%-14s : %s\n" "Uptime"       "$uptime"
printf "%-14s : %s\n" "Users Login"  "$users"
printf "%-14s : %s\n" "IP Address"   "$ip"

awk 'BEGIN{print "--------------------------------------------"}'

printf "%-14s : %s\n" "CPU Model"    "$cpu_model"
printf "%-14s : %s\n" "Cores"        "$cores"
printf "%-14s : %s\n" "Threads"      "$threads"
printf "%-14s : %s\n" "Load Avg"     "$load (1m/5m/15m)"
printf "%-14s : %s\n" "CPU Temp"     "$cpu_temp"
printf "%-14s : %s\n" "GPU Temp"     "$gpu_temp"

awk 'BEGIN{print "--------------------------------------------"}'

printf "%-14s : %s\n" "RAM"          "$ram"
printf "%-14s : %s\n" "Swap"         "$swap"
printf "%-14s : %s\n" "Disk (/)"     "$disk"

awk 'BEGIN{print "--------------------------------------------"}'

printf "%-14s : %s\n" "Total Proses" "$total_proc"
printf "%-14s : %s\n" "Running"      "$run_proc"

echo ""
echo "Top 3 CPU:"
ps aux --no-header | sort -rk3 | head -3 | \
    awk '{printf "  %-25s CPU: %5s%%  MEM: %5s%%\n", substr($11,1,25), $3, $4}'

echo ""
echo "Top 3 Memory:"
ps aux --no-header | sort -rk4 | head -3 | \
    awk '{printf "  %-25s MEM: %5s%%  CPU: %5s%%\n", substr($11,1,25), $4, $3}'


