#!/bin/sh
# newapi-host-agent · 幂等安装脚本(以 root 运行)。
# 重复执行无害——可用于:首次安装、Lightsail 启动脚本(Launch script)、黄金快照、补装。
#
# 用法:
#   MONITOR_URL=http://172.26.10.97:8090 INGEST_TOKEN=xxx NODE_NAME=Ubuntu-NexusAPI-Slave-1 \
#     sudo -E sh install-agent.sh
#
# NODE_NAME 建议填该机对应的 Lightsail 实例名(便于和云侧指标对应);留空则用 hostname。
set -eu

DEST=/opt/nexus-hostagent
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

: "${MONITOR_URL:?请设置 MONITOR_URL}"
: "${INGEST_TOKEN:?请设置 INGEST_TOKEN}"
NODE_NAME="${NODE_NAME:-$(hostname)}"

mkdir -p "$DEST"
install -m 0755 "$SRC_DIR/report.sh" "$DEST/report.sh"

# 写配置(600,含 token,不入 git)。
umask 077
cat > "$DEST/agent.env" <<EOF
MONITOR_URL=$MONITOR_URL
INGEST_TOKEN=$INGEST_TOKEN
NODE_NAME=$NODE_NAME
EOF
chmod 600 "$DEST/agent.env"

install -m 0644 "$SRC_DIR/systemd/nexus-hostagent.service" /etc/systemd/system/nexus-hostagent.service
install -m 0644 "$SRC_DIR/systemd/nexus-hostagent.timer"   /etc/systemd/system/nexus-hostagent.timer

systemctl daemon-reload
systemctl enable --now nexus-hostagent.timer

echo "已安装到 $DEST,timer 已启用(每 60s)。立即测试一次:"
echo "  sudo systemctl start nexus-hostagent.service && journalctl -u nexus-hostagent.service -n 20 --no-pager"
