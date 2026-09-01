# Agents.md — 仓库约定

本文件面向在本仓库中工作的 AI Agent 与协作者，说明项目结构、常用命令和必须遵守的规则。

## 项目简介

Personal Todo Vault 是一个面向**个人使用与私有部署**的待办事项服务：待办、进度、邮件提醒和 Markdown 笔记保存在本机 SQLite 数据库与 `notes/` 目录；可选地通过坚果云 WebDAV 做云端备份。不依赖前端框架或外部 SaaS。

## 技术栈

- 前端：单文件原生 HTML/CSS/JS（`index.html`），工作台式多页面 + hash 路由
- 服务端：Node.js 原生 `http` 模块（`server.js`）
- 数据库：`sql.js`（SQLite WebAssembly，`sqlite.js`）
- 邮件：`nodemailer`（`email.js`）
- 配置：`appConfig.js`（AES-256-GCM 加密保存，密钥本地化）
- 云端备份：坚果云 WebDAV（`cloudBackup.js`）
- 日志控制台：`loghub.js`（stdout 捕获 + 环形缓冲 + 原生 WebSocket）
- Linux 部署：`deploy/`（`install.sh` 一键安装 + systemd，`start.sh` 前台调试）

## 常用命令

```bash
npm start          # 启动服务（默认 http://127.0.0.1:8238）
npm run check      # 语法检查（node --check server.js）
bash deploy/start.sh   # Linux 前台启动（调试用）
sudo bash deploy/install.sh  # Linux 一键安装/更新（systemd 后台服务）
```

## 文档同步规则（必须遵守）

> **只要代码有任何变动（新增、修改、删除功能或配置项），都必须同步更新相关文档。**

涉及的范围：

- `README.md`：功能一览、使用与部署、备份策略、环境变量、项目结构。
- `SPEC.md`：产品与技术规格、数据模型、API、工程结构。
- `.env.example`：环境变量默认值示例，新增或修改环境变量时必须同步。
- `agents.md`：本文件自身；规则或结构变化时同步。

## 代码与目录约定

```text
personal-todo-vault/
├── appConfig.js       # 加密配置读取、保存、脱敏输出
├── cloudBackup.js     # WebDAV 备份：每日带日期快照 / 内容寻址增量备份
├── email.js           # SMTP 邮件与测试邮件
├── index.html         # 工作台式前端页面（导航 + 待办 + 运行日志）
├── loghub.js          # 日志汇聚 + WebSocket 实时控制台
├── server.js          # HTTP API、提醒与备份定时器（每日/间隔模式调度）
├── sqlite.js          # SQLite 初始化、迁移与原子保存
├── deploy/
│   ├── install.sh     # Linux 一键安装：NodeJS 检测/安装 + npm 镜像 + systemd
│   ├── start.sh       # 前台启动脚本（调试用）
│   ├── DEPLOY.md      # Linux 服务器部署指南（逐步操作）
│   └── todo-vault.service  # systemd 服务模板（参考）
├── notes/.gitkeep     # 空笔记目录占位；真实笔记不提交
├── .env.example       # 不含秘密的环境变量示例
├── SPEC.md            # 产品与技术规格
└── package.json       # Node.js 依赖与脚本
```

- 运行时个人数据（`todo.db`、`notes/*.md`、`backups/`、`config.local.*`、`.env*`）一律不提交 Git，见 `.gitignore`。
- 待办 API 字段使用 camelCase（如 `categoryId`、`reminderMode`、`noteFile`）。
- 提交前运行 `npm run check` 确认语法无误。
- 云备份相关行为改动时，重点核对 `README.md` 的「备份结构与策略」与 `SPEC.md` 的「4.4 云端备份」。
- 日志控制台或 Linux 部署相关改动时，重点核对 `README.md` 的「工作台与运行日志」「部署」与 `SPEC.md` 的「4.5 运行日志控制台」「4.6 Linux 部署脚本」。
