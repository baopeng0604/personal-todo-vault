#!/usr/bin/env bash
# =============================================================================
# Personal Todo Vault - 前台启动脚本
#
# 在终端前台运行服务（便于调试，日志直接打印到当前终端）。
# 生产环境建议改用后台服务：sudo bash deploy/install.sh
#
# 用法：
#   bash deploy/start.sh
#
# 说明：
#   - 自动检查 NodeJS，缺失或版本过低时提示先运行 install.sh
#   - 支持 NODE_BIN 覆盖（如 NODE_BIN=/opt/todo-vault/node/bin/node bash deploy/start.sh）
#   - 按 Ctrl+C 停止
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
REQUIRED_NODE_MAJOR=20
NODE_BIN="${NODE_BIN:-$(command -v node 2>/dev/null || true)}"

log()  { echo -e "\033[1;32m[TodoVault]\033[0m $*"; }
warn() { echo -e "\033[1;33m[TodoVault]\033[0m $*"; }
die()  { echo -e "\033[1;31m[TodoVault]\033[0m $*" >&2; exit 1; }

# ── 1. 检查 NodeJS ─────────────────────────────────────────────
if [ -z "$NODE_BIN" ] || [ ! -x "$NODE_BIN" ]; then
    warn "未找到 NodeJS 命令。"
    warn "请先运行一键安装脚本（自动检测/安装 NodeJS 并配置国内镜像）："
    warn "  sudo bash $APP_DIR/deploy/install.sh"
    warn "安装完成后，Node 会写入 ~/.bashrc；重新登录或执行 source ~/.bashrc 后再试。"
    exit 1
fi

NODE_VERSION="$("$NODE_BIN" -v 2>/dev/null | sed 's/^v//')"
NODE_MAJOR="${NODE_VERSION%%.*}"
if [ "${NODE_MAJOR:-0}" -lt "$REQUIRED_NODE_MAJOR" ]; then
    die "当前 NodeJS v$NODE_VERSION 低于要求的 v$REQUIRED_NODE_MAJOR，请运行 sudo bash $APP_DIR/deploy/install.sh 自动升级。"
fi

log "NodeJS v$NODE_VERSION 检测通过，启动服务（Ctrl+C 停止）..."

# ── 2. 启动 ────────────────────────────────────────────────────
cd "$APP_DIR"
exec "$NODE_BIN" server.js
