#!/usr/bin/env bash
# =============================================================================
# Personal Todo Vault - 部署第一步：检测并安装 NodeJS
#
# 功能：
#   1. 自动检测 CPU 架构（x64 / ARM64 / ARMv7，可用 NODE_ARCH 覆盖）
#   2. 检测 PATH 及常见手动安装路径（~/.local/nodejs、/usr/local/bin 等）的 NodeJS
#   3. 要求主版本 >= 20；缺失或过低时，从国内镜像下载二进制压缩包解压到
#      ~/.local/nodejs（默认），不影响系统自带的 Node
#
# 用法：
#   sudo bash deploy/step1-node.sh
#
# 可选环境变量：
#   NODE_MAJOR        要安装的 Node 主版本（默认 22）
#   NODE_VERSION      指定完整版本（如 v22.14.0）；留空自动探测
#   NODE_MIRROR       Node 二进制镜像（默认 registry.npmmirror.com）
#   NODE_INSTALL_DIR  解压目录（默认 ~/.local/nodejs）
#   NODE_ARCH         手动指定架构（如 linux-armv7l）
#
# 可重复运行：已检测到可用的 NodeJS 时会直接复用。
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-node.sh
source "$SCRIPT_DIR/lib-node.sh"

require_root
ensure_node

log "第一步完成：NodeJS v$("$NODE_BIN" -v)"
log "  Node 路径: $NODE_BIN"
log "  下一步:    sudo bash deploy/step2-mirror.sh"
