#!/usr/bin/env bash
# =============================================================================
# Personal Todo Vault - Linux systemd 一键安装/更新脚本（入口）
#
# 本脚本是「分步部署脚本」的一键封装，依次执行：
#   step1-node.sh    检测并安装 NodeJS（>= 20，国内镜像，解压式安装）
#   step2-mirror.sh  设置 npm 国内镜像并安装依赖
#   step3-service.sh 生成并启动 systemd 后台服务（开机自启、崩溃自动重启）
#
# 如需分步执行（每步可单独调试、单独重跑），直接运行 deploy/step*.sh 即可。
#
# 用法（需 root，或 sudo）：
#   sudo bash deploy/install.sh
#
# 可选环境变量：
#   TODO_VAULT_DIR     安装目录（默认 /opt/todo-vault）
#   TODO_VAULT_USER    服务运行用户（默认 root）
#   TODO_VAULT_REPO    仓库地址；目录不存在且设置了它时用 git clone
#   NODE_MAJOR         Node 主版本（默认 22，即当前 LTS）
#   NODE_VERSION       指定完整版本（如 v22.14.0）；留空自动探测
#   NODE_MIRROR        Node 二进制镜像（默认 registry.npmmirror.com，树莓派等实测可用）
#   NPM_REGISTRY       npm 镜像源（默认 npmmirror）
#   CONSOLE_TOKEN      日志控制台访问口令（可选，写入 .env）
#
# 重复运行 = 更新（git pull + 重启服务）
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-node.sh
source "$SCRIPT_DIR/lib-node.sh"

# ── 0. 权限检查 ────────────────────────────────────────────────
require_root

# ── 1. 获取/更新代码 ───────────────────────────────────────────
REPO_URL="${TODO_VAULT_REPO:-}"
if [ -d "$APP_DIR/.git" ]; then
    log "检测到 $APP_DIR 已存在（git 仓库），执行更新..."
    git -C "$APP_DIR" fetch origin
    git -C "$APP_DIR" reset --hard "origin/$(git -C "$APP_DIR" branch --show-current 2>/dev/null || echo master)"
elif [ -d "$APP_DIR" ]; then
    log "检测到 $APP_DIR 已存在，跳过代码获取"
elif [ -n "$REPO_URL" ]; then
    log "克隆代码到 $APP_DIR ..."
    mkdir -p "$(dirname "$APP_DIR")"
    git clone --depth 1 "$REPO_URL" "$APP_DIR"
elif [ -f "$SCRIPT_DIR/../server.js" ]; then
    log "从当前项目目录复制代码到 $APP_DIR ..."
    mkdir -p "$APP_DIR"
    tar --exclude='.git' --exclude='node_modules' --exclude='todo.db' \
        --exclude='backups' --exclude='config.local.*' --exclude='.env' \
        -C "$SCRIPT_DIR/.." -cf - . | tar -C "$APP_DIR" -xf -
else
    die "未找到代码来源：请设置 TODO_VAULT_REPO 或在项目目录内运行本脚本"
fi

# ── 2. 依次执行三个部署步骤 ─────────────────────────────────────
for step in step1-node step2-mirror step3-service; do
    log ">>> 执行 $step.sh ..."
    bash "$SCRIPT_DIR/$step.sh"
done

log "✅ 一键安装完成，服务已启动：$SERVICE_NAME"
