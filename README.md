# Personal Todo Vault

一个面向**个人使用与私有部署**的待办事项服务：待办、进度、提醒和 Markdown 笔记保存在你自己的设备上；可选地通过坚果云 WebDAV 做加密配置下的云端备份。项目使用原生 Node.js HTTP 服务与 SQLite（sql.js），不依赖前端框架或外部 SaaS。

> [!WARNING]
> 本项目目前**没有登录、权限管理或多用户隔离机制**。请只部署在可信的本机、局域网、VPN 或已由反向代理提供身份验证的网络中；**不要直接将端口暴露到公网**。

## 为什么它不同于一般待办应用？

- **一条待办，一份 Markdown 上下文**：每个待办都有独立笔记，可记录目标、步骤、链接、复盘和资料，而不是只有一行标题。
- **个人优先、数据在自己手里**：运行数据是本机 SQLite 数据库和 Markdown 文件；无需注册第三方账户，也不把待办上传到应用服务商。
- **为长期事项设计的进度与提醒**：支持 0–100% 进度，达到 100% 自动完成；提醒可单次、每周指定星期持续重复，或按指定次数重复。
- **安全的配置中心**：邮件和坚果云设置均在页面中保存、测试；密码不会回显，保存时使用 AES-256-GCM 加密，密钥与配置文件均不进入 Git。
- **适合自托管的云端备份**：默认「每日备份」——每天凌晨检测到数据有变化时，才上传一个带日期的 gzip 快照并只保留最近 10 份；也可切换为原「按间隔增量备份」模式。数据库和每份 Markdown 笔记分别进行 SHA-256 内容寻址、gzip 压缩和增量上传。
- **低依赖、便于私有部署**：原生 HTML/CSS/JavaScript + Node.js 原生 HTTP + SQLite WASM，部署和迁移简单。

## 功能一览

- 待办创建、编辑、完成、删除，按分类筛选
- 自定义分类、图标、分类排序
- 每条待办关联独立 Markdown 笔记，支持编辑、保存与安全预览
- 进度记录（0–100%），100% 自动标记完成
- 完成进度概览，重点展示当前待完成工作
- 明暗主题与移动端适配
- 邮件提醒：单次、每周指定星期、指定次数重复；已完成待办自动停止提醒
- 配置中心：SMTP、收件人、坚果云 WebDAV、备份模式与每日备份时间，均可保存和测试
- 坚果云 WebDAV 备份：默认「每日备份」或「按间隔备份」均有变化才上传带日期的 gzip 快照，保留最近 10 份
- SQLite 原子写入、本地滚动备份（默认保留最近 10 份）
- 工作台式多页面界面：侧边导航 + hash 路由，待办清单与运行日志等页面互相切换
- 运行日志控制台：通过 WebSocket 实时推送服务器输出，辅助排查错误（支持访问口令）
- Linux 一键部署：自动检测/安装 NodeJS（国内镜像、解压式安装不影响系统）、配置 npm 镜像并生成 systemd 后台服务
- 兼容从旧版 `data.json` 迁移到 SQLite

## 技术栈

| 层级 | 实现 |
|---|---|
| 前端 | 单文件原生 HTML、CSS、JavaScript（工作台式多页面 + hash 路由） |
| 服务端 | Node.js 原生 `http` 模块 |
| 数据库 | `sql.js`（SQLite WebAssembly） |
| 邮件 | `nodemailer` |
| 笔记 | 本地 `notes/<todo-id>.md` |
| 云端备份 | 坚果云 WebDAV（标准 Basic Auth） |
| 日志推送 | 原生 WebSocket（`loghub.js`，零额外依赖） |

## 快速开始

### 要求

- Node.js **20 或更高版本**
- npm

```bash
git clone https://github.com/nerkeler/personal-todo-vault.git
cd personal-todo-vault
npm ci
npm start
```

默认只绑定本机地址，打开：<http://127.0.0.1:8238/>。

首次启动会创建：

```text
todo.db        # SQLite 数据库（个人数据，不提交）
notes/         # 每条待办的 Markdown 笔记（个人数据，不提交）
backups/       # 本地数据库滚动备份（个人数据，不提交）
config.local.* # 加密的配置与机器本地密钥（不提交）
```

## 网络访问与安全

### 本机访问（推荐开发环境）

```bash
npm start
```

默认监听 `127.0.0.1:8238`，只能由当前设备访问。

### 局域网访问

仅在可信局域网内使用时，绑定全部网卡：

```bash
HOST=0.0.0.0 PORT=8238 npm start
```

之后可使用服务器局域网 IP 加端口访问，例如 `http://<server-lan-ip>:8238/`。

> 因为应用没有内置登录，局域网中能访问该地址的人都能读取和修改待办数据。需要跨网络访问时，请优先使用 Tailscale、WireGuard 等 VPN；或在 Nginx/Caddy 后增加 HTTPS 与身份验证。不要通过路由器端口映射直接公开服务。

## 部署

> 完整的分步操作见 [deploy/DEPLOY.md](deploy/DEPLOY.md)，以下为概要。

### 方式一：Linux 一键安装脚本（推荐）

适合在 Linux 服务器上快速部署并以后台服务方式常驻运行。脚本会自动：

1. 检测 NodeJS 版本（要求 ≥ 20）；缺失或过低时，优先通过**国内镜像下载二进制压缩包**解压到用户目录（默认 `~/.local/nodejs`），不污染系统自带的 Node。
2. 自动配置 npm 国内镜像源（默认 `https://registry.npmmirror.com`）。
3. 安装依赖、生成 `.env`、写入 systemd 服务并设置**开机自启 + 崩溃自动重启**。

```bash
# 把项目放到 /opt/todo-vault（或用仓库 URL 让脚本自动克隆）
cd /opt/todo-vault
sudo bash deploy/install.sh
```

可选环境变量：

```bash
sudo TODO_VAULT_DIR=/opt/todo-vault TODO_VAULT_USER=root \
     CONSOLE_TOKEN=your-log-token bash deploy/install.sh
```

- `TODO_VAULT_DIR`：安装目录（默认 `/opt/todo-vault`）
- `TODO_VAULT_USER`：服务运行用户（默认 `root`）
- `CONSOLE_TOKEN`：运行日志控制台访问口令（写入 `.env`）
- `NODE_MAJOR` / `NODE_VERSION`：指定要安装的 Node 主版本或完整版本
- `NODE_MIRROR` / `NPM_REGISTRY`：自定义 Node 与 npm 镜像

重复运行脚本 = 更新代码并重启服务。

前台调试（日志直接打印到当前终端）：

```bash
bash deploy/start.sh
```

常用运维命令：

```bash
sudo systemctl status todo-vault       # 查看状态
sudo journalctl -u todo-vault -f       # 实时日志
sudo systemctl restart todo-vault      # 重启
```

### 方式二：直接运行

适合开发、个人电脑或已有进程守护工具的环境：

```bash
cd /path/to/personal-todo-vault
npm ci
HOST=0.0.0.0 PORT=8238 npm start
```

### 方式三：手动配置 systemd（可选）

> 一键安装脚本（方式一）会自动完成下述步骤；这里仅供不适用脚本或想手动管理的场景参考。

1. 将项目放到专用目录，并安装依赖：

   ```bash
   sudo mkdir -p /opt/personal-todo-vault
   sudo chown "$USER":"$USER" /opt/personal-todo-vault
   git clone https://github.com/nerkeler/personal-todo-vault.git /opt/personal-todo-vault
   cd /opt/personal-todo-vault
   npm ci
   ```

2. 创建 `/etc/systemd/system/personal-todo-vault.service`：

   ```ini
   [Unit]
   Description=Personal Todo Vault
   After=network.target

   [Service]
   Type=simple
   User=YOUR_LINUX_USER
   WorkingDirectory=/opt/personal-todo-vault
   Environment=NODE_ENV=production
   Environment=HOST=127.0.0.1
   Environment=PORT=8238
   ExecStart=/usr/bin/node /opt/personal-todo-vault/server.js
   Restart=on-failure
   RestartSec=5

   [Install]
   WantedBy=multi-user.target
   ```

   将 `YOUR_LINUX_USER` 改为实际 Linux 用户。若明确只在可信局域网内使用，可把 `HOST=127.0.0.1` 改为 `HOST=0.0.0.0`。

3. 启用并查看状态：

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now personal-todo-vault
   sudo systemctl status personal-todo-vault
   ```

4. 常用运维命令：

   ```bash
   sudo systemctl restart personal-todo-vault
   sudo journalctl -u personal-todo-vault -f
   ```

### 更新部署

先在页面执行一次云端或本地备份，再更新代码：

```bash
cd /opt/personal-todo-vault
git pull --ff-only
npm ci
sudo systemctl restart personal-todo-vault
```

运行数据、加密配置和本地备份目录已经在 `.gitignore` 中，不会被 `git pull` 覆盖。

## 工作台与运行日志

应用采用**工作台式多页面**结构：左侧导航 + hash 路由，页面在浏览器内切换、不刷新。当前包含两个页面：

| 页面 | 路由 | 说明 |
|---|---|---|
| 待办清单 | `#/todos` | 原有待办主页面（默认页） |
| 运行日志 | `#/logs` | 实时查看服务器输出，辅助判断是否有错误 |

### 运行日志页

日志页通过**原生 WebSocket**（`loghub.js`，零额外依赖）实时接收服务器端 `console` 输出：

- 连接后先推送最近最多 1000 条历史日志，之后增量实时追加。
- 报错（`error` / `错误` / `✗` / `fail`）自动标红，警告标黄。
- 顶部状态灯实时反映是否「运行正常」或「近期有报错」；支持暂停/恢复自动滚动。
- 断开后每 2 秒自动重连。

直接访问 `/console` 也可获得独立的全屏日志控制台页面（功能相同）。

### 日志访问口令

默认本地调试不设口令。部署到局域网/服务器时，建议在 `.env` 中设置 `CONSOLE_TOKEN`，则打开 `#/logs` 或 `/console` 需要输入口令；未登录时 WebSocket 与状态接口均返回未授权。

```bash
# .env
CONSOLE_TOKEN=your-secret-token
```

## 配置中心

点击页面右上角的齿轮可打开唯一配置入口。邮件和坚果云配置都可以输入、保存和连接测试。

### 邮件提醒（SMTP）

可设置 SMTP 服务器、端口、SSL/TLS、账号、授权码、发件人名称、发件人邮箱和收件人。

- 密码/授权码只写入本机加密配置，页面不会回显明文。
- 先点击“保存配置”，再点击“测试邮件”。
- 许多邮箱服务要求使用**应用密码/授权码**，而不是网页登录密码。
- 每分钟由服务端检查提醒；每条待办每天最多发送一次。

提醒模式：

| 模式 | 行为 |
|---|---|
| 单次 | 到达设定时间后发送一次，并自动关闭 |
| 每周重复 | 在选中的星期按时持续发送，直到手动关闭或待办完成 |
| 重复 N 次 | 在选中的星期发送，累计达到设定次数后自动关闭 |

### 坚果云 WebDAV 备份

在配置中心填写并保存：

```text
WebDAV 地址：https://dav.jianguoyun.com/dav/
账号：坚果云登录邮箱/账号
应用密码：坚果云「第三方应用密码」，不是网页登录密码
备份目录：todo-app-backups（可自行修改）
```

保存后可点击“测试坚果云”，成功后再点击“立即备份”。应用密码请在坚果云的「安全选项 / 第三方应用管理」中创建。

#### 备份结构与策略

```text
todo-app-backups/
├── objects/
│   ├── database/<sha256>.db.gz
│   └── notes/<sha256>.md.gz
├── snapshots/<timestamp>-<random>.json
└── latest.json
```

- `todo.db` 和每个 Markdown 笔记独立计算 SHA-256；只有新内容或变更内容上传，未变化对象会复用。
- 每次备份生成一份完整快照清单；`latest.json` 指向最新快照。
- 删除的笔记不会出现在最新快照中；历史快照和对象默认保留，便于保留历史版本。
- 这是**单向备份**，不是双向同步。请不要直接在坚果云目录中编辑对象文件。
- WebDAV 密码和本机配置密钥不会上传到坚果云。

#### 带日期的快照备份（两种模式共用）

配置中心的「备份模式」可选**每日备份**（默认）或**按间隔备份**；两者都产生按日期组织的快照，区别只在触发频率：

```text
todo-app-backups/
└── daily/
    └── 2026-09-02/
        ├── todo.db.gz
        └── notes/<笔记名>.md.gz
```

- 每日备份：每天在指定时间（默认 `00:10`）自动执行一次；按间隔备份：每 `intervalHours` 小时检测一次。两者都可点击「立即备份」手动触发。
- 只有当数据库或笔记内容相比上次发生**新增、删除或更改**时才会上传；没有变化则跳过，不产生网络请求和额外存储。
- 只保留**最近 10 份**日期目录，更早的会自动从坚果云清理，避免磁盘与云端空间无限增长。
- 本地状态记录在 `backups/daily-state.json`，用于判断数据是否变化。

## 数据与隐私

以下文件全部是运行时私有数据，默认被 Git 忽略：

| 路径 | 内容 |
|---|---|
| `todo.db` | 待办、分类、提醒等 SQLite 数据 |
| `notes/*.md` | 每条待办关联的 Markdown 笔记 |
| `backups/` | 本机数据库滚动备份 |
| `config.local.json` | AES-GCM 加密后的 SMTP/WebDAV 设置 |
| `config.local.key` | 当前设备的配置加密密钥 |
| `.env` / `.env.local` | 可选环境变量覆盖文件 |
| `data.json` | 旧版导入数据（仅首次迁移时使用） |

### 配置加密说明

页面保存的配置写入 `config.local.json`，整个配置包使用 AES-256-GCM 加密；机器本地密钥保存在 `config.local.key`，或由 `TODO_CONFIG_SECRET` 环境变量提供。

- 请同时妥善备份 `config.local.json` 和 `config.local.key`；只有配置文件而没有同一把密钥时，无法解密密码。
- 不要把这两个文件、应用密码或数据库提交到 Git，也不要发到聊天记录中。
- 需要在另一台服务器恢复配置时，可在安全渠道迁移这两个文件，或重新在配置中心填写配置。

## 可选环境变量

配置中心是首选方式。以下变量适合首次部署、自动化或无界面环境提供默认值：

```bash
# 服务绑定
HOST=127.0.0.1
PORT=8238

# 运行日志控制台访问口令（可选；设置后 #/logs 与 /console 需口令）
# CONSOLE_TOKEN=

# SMTP
TODO_SMTP_HOST=smtp.example.com
TODO_SMTP_PORT=465
TODO_SMTP_SECURE=true
TODO_SMTP_USER=your-account@example.com
TODO_SMTP_PASS=your-smtp-app-password
TODO_SMTP_FROM=your-account@example.com
TODO_MAIL_RECIPIENTS=recipient@example.com

# 坚果云 WebDAV
TODO_WEBDAV_URL=https://dav.jianguoyun.com/dav/
TODO_WEBDAV_USERNAME=your-jianguoyun-account@example.com
TODO_WEBDAV_PASSWORD=your-jianguoyun-app-password
TODO_WEBDAV_BACKUP_DIR=todo-app-backups
# daily = 每日备份（默认，固定时间触发）；interval = 按间隔备份；两者均有变化才备份并保留最近 10 份
TODO_BACKUP_MODE=daily
# 每日备份时间（仅 daily 模式生效，24 小时制 HH:MM）
TODO_BACKUP_TIME=00:10
TODO_BACKUP_AUTO=false
TODO_BACKUP_INTERVAL_HOURS=24
```

可以复制 `.env.example` 作为自己的本地参考文件，但服务不会自动读取 `.env`；请通过 systemd `Environment=`、Shell 环境变量或其他进程管理工具注入。

## 数据迁移与恢复

- 若首次启动时不存在 `todo.db`、但根目录存在旧版 `data.json`，服务会自动迁移数据到 SQLite。
- 已存在 `todo.db` 时不会重复导入 `data.json`。
- 本地保存采用临时文件、`fsync` 和原子替换，并保留最近 10 份滚动数据库备份。
- 坚果云备份支持两种模式：**每日备份**与**按间隔备份**，均在有数据变化时上传带日期的 gzip 快照并保留最近 10 份；恢复流程应取回相应日期目录下的数据库/笔记对象。执行恢复前，请先停止服务并备份现有运行目录。

## API 概览

所有 JSON 请求使用 `Content-Type: application/json`。普通 JSON 请求体上限 2 MiB，Markdown 笔记请求体上限 4 MiB。

| Method | Endpoint | 说明 |
|---|---|---|
| GET / POST | `/api/categories` | 获取或创建分类 |
| PATCH / DELETE | `/api/categories/:id` | 修改或删除分类 |
| PATCH | `/api/categories/reorder` | 调整分类顺序 |
| GET / POST | `/api/todos` | 获取或创建待办，可用 `?categoryId=` 过滤 |
| PATCH / DELETE | `/api/todos/:id` | 更新或删除待办、进度、提醒 |
| GET / PUT | `/api/todos/:id/note` | 读取或保存关联 Markdown 笔记 |
| GET / PUT | `/api/settings` | 读取或保存脱敏后的统一配置 |
| POST | `/api/settings/test-email` | 测试 SMTP 配置 |
| GET | `/api/backup/status` | 获取坚果云备份状态（不返回密码） |
| POST | `/api/backup/test` | 测试坚果云 WebDAV 配置 |
| POST | `/api/backup/run` | 立即上传云端备份 |
| GET | `/api/icons` | 获取预设分类图标 |
| GET | `/console` | 独立运行日志控制台页面 |
| POST | `/console/login` | 提交日志访问口令 |
| GET | `/console/status` | 日志缓冲与近期是否报错的状态 |
| WS | `/console/ws` | 实时日志 WebSocket 通道 |

待办 API 使用 camelCase 字段，例如 `categoryId`、`createdAt`、`reminderEnabled`、`reminderTime`、`reminderMode`、`reminderWeekdays`、`reminderRepeatCount`、`creatorEmail`、`noteFile`。

## 项目结构

```text
personal-todo-vault/
├── appConfig.js       # 加密的本地配置读取、保存与脱敏输出
├── cloudBackup.js     # WebDAV 备份：每日带日期快照 / 内容寻址增量备份
├── email.js           # SMTP 邮件与测试邮件
├── index.html         # 工作台式前端页面（导航 + 待办 + 运行日志）
├── loghub.js          # 日志汇聚 + WebSocket 实时控制台
├── server.js          # HTTP API、提醒与备份定时器（每日/间隔模式调度）
├── sqlite.js          # SQLite 初始化、迁移与原子保存
├── sql-wasm.*         # SQLite WASM 运行时
├── deploy/
│   ├── install.sh     # Linux 一键安装：NodeJS 检测/安装 + npm 镜像 + systemd
│   ├── start.sh       # 前台启动脚本（调试用）
│   ├── DEPLOY.md      # Linux 服务器部署指南（逐步操作）
│   └── todo-vault.service  # systemd 服务模板（参考）
├── notes/.gitkeep     # 空笔记目录占位；真实笔记不提交
├── .env.example       # 不含秘密的环境变量示例
├── agents.md          # 仓库约定：代码变动须同步更新相关文档
├── SPEC.md            # 产品与技术规格
└── package.json       # Node.js 依赖与脚本
```

## 开发检查

```bash
npm run check
```

## 公开仓库约定

本仓库只包含应用代码、文档和无敏感信息的示例文件；不包含真实待办、Markdown 笔记、SQLite 数据库、备份、密码、应用授权码或历史提交记录。部署后产生的个人数据始终保留在你自己的运行环境中。
