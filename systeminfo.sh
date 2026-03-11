#!/bin/bash

echo "------ SYSTEM MONITOR ------"
echo

users=$(who | wc -l)
os=$(grep PRETTY_NAME /etc/os-release | cut -d '"' -f2)
uptime=$(uptime -p | sed 's/up //')
ip=$(hostname -I | awk '{print $1}')

cpu_model=$(lscpu | awk -F: '/Model name/ {print $2}' | sed 's/^ *//')
core=$(lscpu | awk '/^Core.s. per socket:/ {c=$NF} /^Socket.s.:/ {s=$NF} END {print c*s}')
thread=$(lscpu | awk -F: '/^CPU\(s\)/ {gsub(/ /,"",$2); print $2}')
cpu=$(top -bn1 | grep load | awk '{printf "%.2f", $(NF-2)}')
load=$(uptime | awk -F'load average:' '{print $2}')

ram=$(free -m | awk 'NR==2{printf "%s/%sMB (%.2f%%)", $3,$2,$3*100/$2}')
disk=$(df -h | awk '$NF=="/"{printf "%s/%s (%s)", $3,$2,$5}')

echo "System"
echo "OS           : $os"
echo "Uptime       : $uptime"
echo "Users        : $users"
echo "IP Address   : $ip"
echo

echo "CPU"
echo "CPU Model    : $cpu_model"
echo "CPU Core     : $core"
echo "CPU Thread   : $thread"
echo "CPU Load     : $cpu"
echo "Load Average : $load"
echo

echo "Memory / Disk"
echo "Memory Usage : $ram"
echo "Disk Usage   : $disk"

