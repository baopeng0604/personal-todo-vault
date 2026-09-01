#!/usr/bin/env bash
# =============================================================================
# Personal Todo Vault - 部署第三步：systemd 服务加载运行
#
# 功能：
#   1. 复用已安装的 NodeJS（找不到时自动回退到检测/安装）
#   2. 首次运行生成 .env（复制 .env.example）；可选注入 CONSOLE_TOKEN
#   3. 生成 /etc/systemd/system/todo-vault.service（崩溃自动重启、开机自启）
#   4. daemon-reload + enable + restart，并检查服务与端口状态
#
# 用法（需 root）：
#   sudo bash deploy/step3-service.sh
#
# 可选环境变量：
#   TODO_VAULT_DIR     项目目录（默认 /opt/todo-vault）
#   TODO_VAULT_USER    服务运行用户（默认 root）
#   CONSOLE_TOKEN      日志控制台访问口令（可选，写入 .env）
#
# 可重复运行：会重新生成服务文件并重启服务，等价于「更新后重启」。
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-node.sh
source "$SCRIPT_DIR/lib-node.sh"

require_root
ensure_node

cd "$APP_DIR"

# ── 1. 生成 .env ───────────────────────────────────────────────
if [ ! -f ".env" ]; then
    cp .env.example .env
    warn "已生成 $APP_DIR/.env，请编辑填入 SMTP / 坚果云等配置后重启服务："
    warn "  sudo nano $APP_DIR/.env && sudo systemctl restart $SERVICE_NAME"
fi
if [ -n "$CONSOLE_TOKEN" ]; then
    if grep -q "^CONSOLE_TOKEN=" .env; then
        sed -i "s|^CONSOLE_TOKEN=.*|CONSOLE_TOKEN=$CONSOLE_TOKEN|" .env
    else
        echo "CONSOLE_TOKEN=$CONSOLE_TOKEN" >> .env
    fi
fi

# ── 2. 生成 systemd 服务 ───────────────────────────────────────
log "写入 systemd 服务 /etc/systemd/system/$SERVICE_NAME.service ..."
cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=Personal Todo Vault
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$APP_DIR
EnvironmentFile=$APP_DIR/.env
ExecStart=$NODE_BIN $APP_DIR/server.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

# ── 3. 检查状态 ────────────────────────────────────────────────
sleep 2
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "✅ 服务已启动并设置开机自启：$SERVICE_NAME"
    log "  查看状态:   systemctl status $SERVICE_NAME"
    log "  实时日志:   journalctl -u $SERVICE_NAME -f"
    log "  网页日志:   http://<服务器IP>:8238/#/logs （或 /console）"
    warn "  如需局域网访问，请把 .env 中的 HOST 改为 0.0.0.0"
else
    warn "服务启动失败，请查看日志：journalctl -u $SERVICE_NAME -n 50"
    exit 1
fi
