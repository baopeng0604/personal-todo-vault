# Personal Todo Vault — Linux 服务器部署指南

本文档说明如何把 Personal Todo Vault 部署到 Linux 服务器，并以后台服务方式常驻运行。部署脚本会自动完成 NodeJS 检测/安装、国内镜像配置、依赖安装与 systemd 服务注册。

## 一、准备服务器

1. 准备一台 Linux 服务器（Debian/Ubuntu、CentOS 等均可），记下公网 IP 和登录凭据。
2. 本地终端 SSH 登录：

```bash
ssh root@你的服务器IP
```

1. 检查脚本依赖的基础命令是否可用（需要 `curl`、`tar`）：

```bash
curl --version && tar --version
```

缺失时先安装（Debian/Ubuntu 示例）：

```bash
apt update && apt install -y curl tar git
```

## 二、获取代码

二选一。

### 方式 A：脚本自动克隆

把代码推到 GitHub/Gitee 后，在安装时通过环境变量 `TODO_VAULT_REPO` 指定仓库地址，脚本会自动 `git clone` 到安装目录：

```bash
sudo TODO_VAULT_REPO=https://github.com/your-name/personal-todo-vault.git bash deploy/install.sh
```

### 方式 B：本地上传（推荐）

在本机把项目打包上传到服务器（排除运行时数据与密钥）：

```bash
tar --exclude='.git' --exclude='node_modules' --exclude='todo.db' \
    --exclude='backups' --exclude='config.local.*' --exclude='.env' \
    -czf todo-vault.tar.gz -C d:\Code\Github\personal-todo-vault .

scp todo-vault.tar.gz root@你的服务器IP:/opt/
```

在服务器上解压：

```bash
mkdir -p /opt/todo-vault
tar -xzf /opt/todo-vault.tar.gz -C /opt/todo-vault
rm /opt/todo-vault.tar.gz
```

## 三、运行一键安装脚本

```bash
cd /opt/todo-vault
sudo bash deploy/install.sh
```

脚本自动完成：

1. **NodeJS 检测与安装**：要求主版本 ≥ 20；缺失或过低时，优先从国内镜像（默认 `https://registry.npmmirror.com/-/binary/node`）下载与 CPU 架构匹配的 Linux 二进制压缩包（自动检测 x64 / ARM64 / ARMv7），解压到用户目录（默认 `~/.local/nodejs`），不污染系统自带的 Node。已手动安装的 Node（位于 `~/.local/nodejs/bin` 等常见路径）会被自动识别复用。
2. **npm 国内镜像**：自动设置 `registry=https://registry.npmmirror.com`。
3. **依赖安装**：执行 `npm ci`（有 lock 文件时）或 `npm install`。
4. **生成** **`.env`**：首次运行复制 `.env.example` 为 `.env`。
5. **注册 systemd 服务**：生成 `/etc/systemd/system/todo-vault.service`（崩溃自动重启、开机自启），并立即启动。

安装完成后终端提示：

```text
✅ 服务已启动并设置开机自启：todo-vault
   网页日志:   http://<服务器IP>:8238/#/logs
```

> 说明：Linux 上 Node 官方发布的是 `tar.xz` 压缩包，解压即用，效果等同于「下载 zip 包解压、不影响原系统」的方式。

### 常用安装变量

```bash
sudo TODO_VAULT_DIR=/opt/todo-vault TODO_VAULT_USER=root \
     CONSOLE_TOKEN=your-log-token bash deploy/install.sh
```

| 变量                | 默认值               | 说明                          |
| ----------------- | ----------------- | --------------------------- |
| `TODO_VAULT_DIR`  | `/opt/todo-vault` | 安装目录                        |
| `TODO_VAULT_USER` | `root`            | 服务运行用户                      |
| `TODO_VAULT_REPO` | 空                 | 仓库地址；目录不存在时自动克隆             |
| `CONSOLE_TOKEN`   | 空                 | 运行日志控制台访问口令，写入 `.env`       |
| `NODE_MAJOR`      | `22`              | 要安装的 Node 主版本               |
| `NODE_VERSION`    | 空                 | 指定完整版本（如 `v22.14.0`），留空自动探测 |
| `NODE_MIRROR`     | npmmirror         | Node 二进制镜像                  |
| `NPM_REGISTRY`    | npmmirror         | npm 镜像源                     |

重复运行脚本 = 更新代码并重启服务。

## 四、编辑 .env 配置

```bash
nano /opt/todo-vault/.env
```

必须修改的关键项：

```bash
# 服务器访问必须设为 0.0.0.0（默认 127.0.0.1 只能本机访问）
HOST=0.0.0.0
PORT=8238

# 建议设置：运行日志控制台访问口令
CONSOLE_TOKEN=换成你自己的强口令
```

SMTP / 坚果云配置建议直接在页面「配置中心」填写，`.env` 里可留空。

保存后重启服务：

```bash
sudo systemctl restart todo-vault
```

## 五、页面配置中心设置

浏览器打开 `http://你的服务器IP:8238/`：

1. 右上角齿轮 → 配置中心：

   - **坚果云 WebDAV**：地址 `https://dav.jianguoyun.com/dav/`、坚果云账号、第三方应用密码、备份目录

   - 备份模式默认「每日备份」，时间默认 `00:10`（有变化才备份，保留最近 10 份）

   - **SMTP 邮件提醒**（可选）
2. 保存配置 → 点「测试坚果云」→ 成功后再点「立即备份」。

## 六、验证部署

```bash
# 服务状态
sudo systemctl status todo-vault

# 服务器端实时日志
sudo journalctl -u todo-vault -f

# 网页日志页（实时推送服务器输出，辅助排查错误）
# 浏览器打开 http://你的服务器IP:8238/#/logs（设了 CONSOLE_TOKEN 需输入口令）
```

访问日志页验证：状态灯为绿色「运行正常」，能看到启动日志实时滚动，即部署成功。

## 七、日常运维

```bash
sudo systemctl restart todo-vault    # 重启
sudo systemctl stop todo-vault       # 停止
sudo journalctl -u todo-vault -n 50  # 查看最近 50 行日志
```

### 更新代码

重新上传新代码包覆盖 `/opt/todo-vault`（注意不要覆盖 `.env`、`todo.db`、`notes/`、`backups/`、`config.local.*`），再执行一次：

```bash
sudo bash deploy/install.sh
```

脚本会自动重启服务。

### 前台调试

```bash
cd /opt/todo-vault && bash deploy/start.sh
```

日志直接打印到当前终端，按 `Ctrl+C` 停止。

## 八、安全提醒

- 应用没有内置登录，若仅自己使用，建议用防火墙把 8238 端口限制为你的 IP，或使用 Tailscale / WireGuard 等 VPN 访问；不要直接把端口映射到公网。

- `CONSOLE_TOKEN` 务必设置，否则日志页任何人可看。

- 首次备份前先在配置中心手动触发一次「立即备份」，确认坚果云连通后再依赖自动备份。

- 运行数据（`todo.db`、`notes/`、`backups/`、`config.local.*`、`.env`）请勿提交到 Git 或上传到公共仓库。

