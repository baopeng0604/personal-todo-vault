#!/usr/bin/env bash
# =============================================================================
# Personal Todo Vault - 部署第二步：设置 npm 国内镜像并安装依赖
#
# 功能：
#   1. 复用第一步安装好的 NodeJS（找不到时自动回退到检测/安装）
#   2. 设置 npm 镜像源（默认 https://registry.npmmirror.com）
#   3. 安装项目依赖（有 package-lock.json 时用 npm ci，否则 npm install）
#
# 用法（需 root）：
#   sudo bash deploy/step2-mirror.sh
#
# 可选环境变量：
#   TODO_VAULT_DIR   项目目录（默认 /opt/todo-vault）
#   NPM_REGISTRY     npm 镜像源（默认 npmmirror）
#
# 可重复运行：会重新安装依赖，网络不通时不会影响系统其余部分。
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-node.sh
source "$SCRIPT_DIR/lib-node.sh"

require_root
ensure_node

NPM_BIN="$(dirname "$NODE_BIN")/npm"

log "设置 npm 镜像源：$NPM_REGISTRY ..."
"$NPM_BIN" config set registry "$NPM_REGISTRY"

log "进入项目目录 $APP_DIR ..."
cd "$APP_DIR"
[ -f package.json ] || die "未找到 package.json，请确认 TODO_VAULT_DIR=$APP_DIR 是项目目录"

log "安装依赖 ..."
if [ -f package-lock.json ]; then
    "$NPM_BIN" ci
else
    "$NPM_BIN" install
fi

log "第二步完成：npm 镜像已设置，依赖已安装"
log "  下一步:    sudo bash deploy/step3-service.sh"
