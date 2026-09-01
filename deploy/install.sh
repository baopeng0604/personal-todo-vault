#!/usr/bin/env bash
# =============================================================================
# Personal Todo Vault - Linux systemd 一键安装/更新脚本
#
# 功能：
#   1. 自动检测 NodeJS 版本（要求 >= 20），缺失或过低时自动安装
#   2. 优先使用「下载二进制压缩包解压到用户目录」的方式安装，不影响系统
#   3. 自动配置 npm 国内镜像（默认 npmmirror）
#   4. 安装依赖、生成 systemd 后台服务（开机自启、崩溃自动重启）
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
#   NODE_MIRROR        Node 二进制镜像（默认 npmmirror）
#   NPM_REGISTRY       npm 镜像源（默认 npmmirror）
#   CONSOLE_TOKEN      日志控制台访问口令（可选，写入 .env）
#
# 重复运行 = 更新（git pull + 重启服务）
# =============================================================================
set -euo pipefail

APP_DIR="${TODO_VAULT_DIR:-/opt/todo-vault}"
SERVICE_USER="${TODO_VAULT_USER:-root}"
SERVICE_NAME="todo-vault"
REPO_URL="${TODO_VAULT_REPO:-}"
REQUIRED_NODE_MAJOR=20
NODE_MAJOR="${NODE_MAJOR:-22}"
NODE_VERSION="${NODE_VERSION:-}"
NODE_MIRROR="${NODE_MIRROR:-https://npmmirror.com/mirrors/node}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
NODE_INSTALL_DIR="${NODE_INSTALL_DIR:-$HOME/.local/nodejs}"
CONSOLE_TOKEN="${CONSOLE_TOKEN:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_BIN=""

log()  { echo -e "\033[1;32m[TodoVault]\033[0m $*"; }
warn() { echo -e "\033[1;33m[TodoVault]\033[0m $*"; }
die()  { echo -e "\033[1;31m[TodoVault]\033[0m $*" >&2; exit 1; }

# ── 0. 权限检查 ────────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || die "请以 root 运行：sudo bash deploy/install.sh"

# 自动检测 CPU 架构（x64 / ARM64 / ARMv7 均支持；可用 NODE_ARCH 手动覆盖）
case "${NODE_ARCH:-$(uname -m)}" in
  linux-x64|x86_64|amd64)      NODE_ARCH="linux-x64" ;;
  linux-arm64|aarch64|arm64)   NODE_ARCH="linux-arm64" ;;
  linux-armv7l|armv7l|armhf|arm) NODE_ARCH="linux-armv7l" ;;
  *) die "不支持的 CPU 架构: ${NODE_ARCH:-$(uname -m)}（可通过 NODE_ARCH 指定，如 linux-arm64）" ;;
esac

# ── 1. 依赖检查 ────────────────────────────────────────────────
for cmd in curl tar; do
    command -v "$cmd" >/dev/null 2>&1 || die "缺少命令: $cmd（Debian/Ubuntu: apt install -y curl tar）"
done

# ── 2. 获取/更新代码 ───────────────────────────────────────────
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
cd "$APP_DIR"

# ── 3. NodeJS 检测与安装 ───────────────────────────────────────
detect_node() {
    if command -v node >/dev/null 2>&1; then
        local v major
        v="$(node -v 2>/dev/null | sed 's/^v//')"
        major="${v%%.*}"
        if [ "${major:-0}" -ge "$REQUIRED_NODE_MAJOR" ]; then
            log "检测到 NodeJS v$v（>= $REQUIRED_NODE_MAJOR），直接复用"
            NODE_BIN="$(command -v node)"
            return 0
        fi
        warn "NodeJS v$v 低于要求的 $REQUIRED_NODE_MAJOR，将自动安装新版本"
    else
        log "未检测到 NodeJS，开始自动安装（国内镜像，解压到 $NODE_INSTALL_DIR，不影响系统）"
    fi
    return 1
}

install_node() {
    if [ -z "$NODE_VERSION" ]; then
        log "探测镜像 $NODE_MIRROR 的最新 v$NODE_MAJOR 版本 ..."
        local listing
        listing="$(curl -fsSL --retry 3 "$NODE_MIRROR/latest-v${NODE_MAJOR}.x/" || die "无法访问 Node 镜像：$NODE_MIRROR")"
        NODE_VERSION="$(echo "$listing" | grep -oE "node-v${NODE_MAJOR}\.[0-9]+\.[0-9]+-${NODE_ARCH}\.tar\.xz" | head -n1 | sed -E "s/node-(v[0-9.]+)-${NODE_ARCH}\.tar\.xz/\1/")"
        [ -n "$NODE_VERSION" ] || die "未能从镜像解析出 Node 版本（可设置 NODE_VERSION 手动指定）"
    fi
    NODE_VERSION="${NODE_VERSION#v}"  # 去掉可能的 v 前缀

    local tarball="node-v${NODE_VERSION}-${NODE_ARCH}.tar.xz"
    local url="$NODE_MIRROR/v${NODE_VERSION}/$tarball"
    log "下载 $url ..."
    curl -fL --retry 3 -o "/tmp/$tarball" "$url" || die "下载失败（可尝试 NODE_MIRROR=https://nodejs.org/dist）"

    log "解压到 $NODE_INSTALL_DIR ..."
    mkdir -p "$NODE_INSTALL_DIR"
    tar -xJf "/tmp/$tarball" -C "$NODE_INSTALL_DIR" --strip-components=1
    rm -f "/tmp/$tarball"

    NODE_BIN="$NODE_INSTALL_DIR/bin/node"
    [ -x "$NODE_BIN" ] || die "Node 安装失败：$NODE_BIN 不存在"

    # 提示用户把 Node 加入 PATH（当前 shell 立即生效）
    export PATH="$NODE_INSTALL_DIR/bin:$PATH"
    if ! grep -q "$NODE_INSTALL_DIR/bin" "$HOME/.bashrc" 2>/dev/null; then
        echo "export PATH=\"$NODE_INSTALL_DIR/bin:\$PATH\"" >> "$HOME/.bashrc"
        warn "已把 Node 写入 $HOME/.bashrc（重新登录后全局可用）"
    fi
}

if ! detect_node; then
    install_node
    log "NodeJS 安装完成：v$("$NODE_BIN" -v)"
fi

NPM_BIN="$(dirname "$NODE_BIN")/npm"

# ── 4. npm 国内镜像 ────────────────────────────────────────────
log "设置 npm 镜像源：$NPM_REGISTRY ..."
"$NPM_BIN" config set registry "$NPM_REGISTRY"

# ── 5. 安装依赖 ────────────────────────────────────────────────
log "安装依赖 ..."
if [ -f package-lock.json ]; then
    "$NPM_BIN" ci
else
    "$NPM_BIN" install
fi

# ── 6. 配置 .env ───────────────────────────────────────────────
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

# ── 7. 生成 systemd 服务 ───────────────────────────────────────
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

# ── 8. 检查状态 ────────────────────────────────────────────────
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
