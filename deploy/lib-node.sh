#!/usr/bin/env bash
# =============================================================================
# Personal Todo Vault - 部署公共函数库（仅供 deploy/step*.sh 通过 source 复用）
#
# 提供：日志输出、CPU 架构检测、NodeJS 检测与安装。
# 本文件不直接执行任何逻辑，只定义函数；由各 step 脚本按需调用。
# =============================================================================

# ── 默认参数（可用环境变量覆盖） ─────────────────────────────
REQUIRED_NODE_MAJOR=20
NODE_MAJOR="${NODE_MAJOR:-22}"
NODE_VERSION="${NODE_VERSION:-}"
NODE_MIRROR="${NODE_MIRROR:-https://registry.npmmirror.com/-/binary/node}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
NODE_INSTALL_DIR="${NODE_INSTALL_DIR:-$HOME/.local/nodejs}"
APP_DIR="${TODO_VAULT_DIR:-/opt/todo-vault}"
SERVICE_USER="${TODO_VAULT_USER:-root}"
SERVICE_NAME="todo-vault"

NODE_BIN=""

# ── 日志工具 ─────────────────────────────────────────────────
log()  { echo -e "\033[1;32m[TodoVault]\033[0m $*"; }
warn() { echo -e "\033[1;33m[TodoVault]\033[0m $*"; }
die()  { echo -e "\033[1;31m[TodoVault]\033[0m $*" >&2; exit 1; }

# ── 权限检查（需要 root） ───────────────────────────────────
require_root() {
    [ "$(id -u)" -eq 0 ] || die "请以 root 运行：sudo bash ${BASH_SOURCE[1]##*/}"
}

# ── CPU 架构自动检测（x64 / ARM64 / ARMv7；可用 NODE_ARCH 覆盖） ──
detect_arch() {
    case "${NODE_ARCH:-$(uname -m)}" in
        linux-x64|x86_64|amd64)        NODE_ARCH="linux-x64" ;;
        linux-arm64|aarch64|arm64)     NODE_ARCH="linux-arm64" ;;
        linux-armv7l|armv7l|armhf|arm) NODE_ARCH="linux-armv7l" ;;
        *) die "不支持的 CPU 架构: ${NODE_ARCH:-$(uname -m)}（可通过 NODE_ARCH 指定，如 linux-arm64）" ;;
    esac
}

# ── 检测已有 NodeJS（要求 >= REQUIRED_NODE_MAJOR） ────────────
# 找到后把绝对路径写入全局变量 NODE_BIN 并返回 0；否则返回 1。
detect_node() {
    local candidates=() bin v major
    # 1. PATH 中的 node
    if command -v node >/dev/null 2>&1; then
        candidates+=("$(command -v node)")
    fi
    # 2. 常见手动安装路径（含默认解压目录 ~/.local/nodejs）
    candidates+=(
        "$NODE_INSTALL_DIR/bin/node"
        "$HOME/.local/nodejs/bin/node"
        "/usr/local/bin/node"
        "/opt/node/bin/node"
    )
    for bin in "${candidates[@]}"; do
        [ -x "$bin" ] || continue
        if ! v="$("$bin" -v 2>/dev/null)"; then
            warn "发现 $bin 但无法执行（可能架构不匹配：系统为 $(uname -m)，该包非本机架构），已忽略"
            continue
        fi
        v="${v#v}"
        [ -n "$v" ] || continue
        major="${v%%.*}"
        if [ "${major:-0}" -ge "$REQUIRED_NODE_MAJOR" ]; then
            NODE_BIN="$bin"
            return 0
        fi
        warn "NodeJS v$v（$bin）低于要求的 $REQUIRED_NODE_MAJOR，将自动安装新版本"
    done
    return 1
}

# ── 安装 NodeJS（国内镜像，解压到用户目录，不影响系统） ────────
install_node() {
    if [ -z "$NODE_VERSION" ]; then
        log "探测镜像 $NODE_MIRROR 的最新 v$NODE_MAJOR 版本 ..."
        local listing
        if ! listing="$(curl -fsSL --connect-timeout 10 --max-time 25 --retry 2 --retry-delay 2 "$NODE_MIRROR/latest-v${NODE_MAJOR}.x/" 2>/dev/null)"; then
            die "无法访问 Node 镜像：$NODE_MIRROR（网络不通或镜像被墙；可设置 NODE_MIRROR 换源，或设置 NODE_VERSION 跳过探测）"
        fi
        NODE_VERSION="$(echo "$listing" | grep -oE "node-v${NODE_MAJOR}\.[0-9]+\.[0-9]+-${NODE_ARCH}\.tar\.xz" | head -n1 | sed -E "s/node-(v[0-9.]+)-${NODE_ARCH}\.tar\.xz/\1/" || true)"
        [ -n "$NODE_VERSION" ] || die "未能从镜像解析出 Node 版本（可设置 NODE_VERSION 手动指定）"
    fi
    NODE_VERSION="${NODE_VERSION#v}"  # 去掉可能的 v 前缀

    local tarball="node-v${NODE_VERSION}-${NODE_ARCH}.tar.xz"
    local url="$NODE_MIRROR/v${NODE_VERSION}/$tarball"
    log "下载 $url ..."
    curl -fL --connect-timeout 15 --retry 3 --retry-delay 2 -o "/tmp/$tarball" "$url" || die "下载失败（可尝试 NODE_MIRROR=https://nodejs.org/dist）"

    log "解压到 $NODE_INSTALL_DIR ..."
    mkdir -p "$NODE_INSTALL_DIR"
    tar -xJf "/tmp/$tarball" -C "$NODE_INSTALL_DIR" --strip-components=1
    rm -f "/tmp/$tarball"

    NODE_BIN="$NODE_INSTALL_DIR/bin/node"
    [ -x "$NODE_BIN" ] || die "Node 安装失败：$NODE_BIN 不存在"
    if ! v="$("$NODE_BIN" -v 2>/dev/null)"; then
        die "Node 二进制无法执行：当前系统架构 $(uname -m) 与 ${NODE_ARCH} 包不匹配（例如 32 位系统误装 arm64 包）。请删除 $NODE_INSTALL_DIR 后重试，或用 NODE_ARCH 指定正确架构"
    fi

    # 提示用户把 Node 加入 PATH（当前 shell 立即生效）
    export PATH="$NODE_INSTALL_DIR/bin:$PATH"
    if ! grep -q "$NODE_INSTALL_DIR/bin" "$HOME/.bashrc" 2>/dev/null; then
        echo "export PATH=\"$NODE_INSTALL_DIR/bin:\$PATH\"" >> "$HOME/.bashrc"
        warn "已把 Node 写入 $HOME/.bashrc（重新登录后全局可用）"
    fi
}

# ── 确保 NodeJS 可用（没有则自动安装） ───────────────────────
ensure_node() {
    detect_arch
    if ! detect_node; then
        log "未检测到 NodeJS，开始自动安装（国内镜像，解压到 $NODE_INSTALL_DIR，不影响系统）"
        install_node
        log "NodeJS 安装完成：v$("$NODE_BIN" -v)"
    else
        log "检测到 NodeJS v$("$NODE_BIN" -v)（$NODE_BIN，>= $REQUIRED_NODE_MAJOR），直接复用"
    fi
    [ -n "$NODE_BIN" ] && [ -x "$NODE_BIN" ] || die "NodeJS 不可用，无法继续"
}
