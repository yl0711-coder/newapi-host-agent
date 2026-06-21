#!/bin/sh
# newapi-host-agent · 主机指标采集并推送给 newapi-monitor。
#
# 采集 AWS 接口拿不到的主机 OS 指标(内存/磁盘/swap/load),POST 给 monitor 的
# /internal/host 接收端点。由 systemd timer 以 oneshot 方式每 60s 拉起一次,
# 跑完即退——无常驻进程、不开端口、几乎零资源占用。
#
# 配置来自 agent.env(EnvironmentFile 注入)或环境变量:
#   MONITOR_URL    monitor 地址,如 http://172.26.10.97:8090
#   INGEST_TOKEN   与 monitor 的 MONITOR_INGEST_TOKEN 一致
#   NODE_NAME      节点名(建议填 Lightsail 实例名,以便和云侧指标对应;默认 hostname)
set -u

CONF="${AGENT_ENV:-/opt/nexus-hostagent/agent.env}"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

: "${MONITOR_URL:?MONITOR_URL 未设置}"
: "${INGEST_TOKEN:?INGEST_TOKEN 未设置}"
NODE_NAME="${NODE_NAME:-$(hostname)}"

# 内存(MB)——从 /proc/meminfo 取,比解析 free 输出更稳。
mem_total_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
mem_avail_kb=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
swap_total_kb=$(awk '/^SwapTotal:/{print $2}' /proc/meminfo)
swap_free_kb=$(awk '/^SwapFree:/{print $2}' /proc/meminfo)
mem_total_mb=$(( mem_total_kb / 1024 ))
mem_avail_mb=$(( mem_avail_kb / 1024 ))
swap_used_mb=$(( (swap_total_kb - swap_free_kb) / 1024 ))

# 根分区使用率(%)。
disk_used_pct=$(df -P / | awk 'NR==2{gsub("%","",$5); print $5}')

# 1 分钟负载。
load1=$(awk '{print $1}' /proc/loadavg)

ts=$(date +%s)

payload=$(printf '{"node":"%s","mem_total_mb":%s,"mem_avail_mb":%s,"swap_used_mb":%s,"disk_used_pct":%s,"load1":%s,"ts":%s}' \
  "$NODE_NAME" "$mem_total_mb" "$mem_avail_mb" "$swap_used_mb" "$disk_used_pct" "$load1" "$ts")

# 推送;失败返回非 0,由 systemd 记入 journald,下个周期自动重试(不累积)。
curl -fsS --max-time 10 \
  -H "Authorization: Bearer ${INGEST_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST "${MONITOR_URL%/}/internal/host" \
  -d "$payload" >/dev/null
