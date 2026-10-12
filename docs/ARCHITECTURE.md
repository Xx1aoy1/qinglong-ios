# 架构与接口说明

本文档说明「青龙助手」如何与青龙面板交互，以及页面流转与构建方案。

## 一、与后端交互的方式

### 1. 基础约定

| 项 | 值 |
| --- | --- |
| 协议 | HTTP/HTTPS（客户端已放开 ATS，支持自签证书） |
| 默认端口 | 5700 |
| 接口前缀 | `/api`（`/open` 与之同路由，用于开放接口令牌） |
| 响应外壳 | `{ "code": 200, "message": "...", "data": ... }` |
| 成功判定 | `code == 200` |
| 未认证 | HTTP 401 + `{ "code": 401 }`，客户端统一触发登出 |

### 2. 认证

```
POST /api/user/login        { username, password }
  → 200 { token, lastip, lastaddr, lastlogon, retries, platform }
  → 420 开启了两步验证 → PUT /api/user/two-factor/login { username, password, code }
  → 400 密码错误 / 410 失败过多（data 为等待秒数）/ 450 未初始化
```

后续请求携带：

```
Authorization: Bearer <token>
User-Agent: QingLong-iOS/<version> (<model>; iOS <version>) Mobile/15E148
```

> 面板按 UA 判定平台（命中 `ios|iphone|ipad|ipod|iwatch` 记为 mobile），每个平台最多 10 个有效 Token。客户端 UA 固定含 `iOS`，确保归入 mobile 槽位。

Token 存储在系统钥匙串（`kSecClassGenericPassword`，`kSecAttrAccessibleAfterFirstUnlock`），按服务器 ID 隔离，支持多面板共存。

### 3. 白名单接口（无需 Token）

`/api/user/login`、`/api/health`、`/api/system`、`/api/user/init`、`/api/user/notification/init`、`/api/user/two-factor/login` 及对应 `/open` 路由。客户端「测试连接」用的 `GET /api/system` 即在其中。

### 4. 客户端使用的接口清单

| 模块 | 接口 |
| --- | --- |
| 系统 | `GET /api/system`、`GET /api/system/config`、`PUT /api/system/config/*`（timezone / lang / panel-title / log-remove-frequency / cron-concurrency / dependence-proxy / node-mirror / python-mirror / linux-mirror / global-ssh-key）、`PUT /api/system/config/dependence-clean`、`GET /api/system/update-check`、`PUT /api/system/update`、`PUT /api/system/reload`、`PUT /api/system/notify` |
| 命令 | `PUT /api/system/command-run`（**流式**，响应头含 `QL-Task-Pid`）、`PUT /api/system/command-stop` |
| 数据 | `PUT /api/system/data/export`（tgz）、`PUT /api/system/data/import`（multipart，字段 `data`）、`GET /api/system/log`、`DELETE /api/system/log` |
| 账号 | `GET/PUT /api/user`、`POST /api/user/login`、`GET /api/user/login-log`、`POST /api/user/logout`、`PUT /api/user/init`、`GET /api/user/two-factor/init`、`PUT /api/user/two-factor/active`、`PUT /api/user/two-factor/deactivate`、`GET/PUT/DELETE /api/user/ip-blacklist`、`GET/PUT /api/user/notification`、`PUT /api/system/auth/reset` |
| 任务 | `GET /api/crons`、`POST/PUT /api/crons`、`GET/PUT/DELETE /api/crons/:id`、`GET /api/crons/detail`、`PUT /api/crons/run`、`/stop`、`/enable`、`/disable`、`/pin`、`/unpin`、`/labels`、`GET /api/crons/:id/log`（顶层额外字段 `logStatus/offset/nextOffset/total/truncated`）、`GET /api/crons/:id/logs`、`GET /api/crons/:id/instances`、`PUT /api/crons/:id/instances/:instanceId/stop` |
| 变量 | `GET /api/envs`、`POST/PUT/DELETE /api/envs`、`GET/PUT/DELETE /api/envs/:id`、`PUT /api/envs/:id/move`、`PUT /api/envs/enable`、`/disable`、`/name`、`/pin`、`/unpin`、`POST/DELETE /api/envs/labels`、`POST /api/envs/upload` |
| 订阅 | `GET /api/subscriptions`、`POST/PUT/DELETE /api/subscriptions`（DELETE 支持 `?force=true`）、`PUT /api/subscriptions/run`、`/stop`、`/enable`、`/disable`、`GET /api/subscriptions/:id/log`、`/logs`、`GET /api/subscriptions/status` |
| 日志 | `GET /api/logs`（嵌套文件树）、`GET /api/logs/detail`、`DELETE /api/logs`、`POST /api/logs/download` |
| 脚本 | `GET /api/scripts`（嵌套树）、`GET /api/scripts/detail`、`POST /api/scripts`、`PUT /api/scripts`、`DELETE /api/scripts`、`PUT /api/scripts/run`、`/stop`、`POST /api/scripts/download`、`PUT /api/scripts/rename` |
| 依赖 | `GET /api/dependencies`、`POST/PUT/DELETE /api/dependencies`、`PUT /api/dependencies/force`、`/reinstall`、`/cancel`、`GET /api/dependencies/:id` |
| 开放 | `GET /api/apps`、`POST/PUT/DELETE /api/apps`、`PUT /api/apps/:id/reset-secret`、`GET /open/auth/token?client_id=&client_secret=` |

### 5. 客户端分层

```
Features (SwiftUI 页面 + @MainActor ViewModel)
      │  只调用 Service
      ▼
Core/Services        ── 组装 Endpoint、解析响应外壳
      ▼
Core/Network APIClient ── URLSession async/await、Token 注入、401 回调、流式 AsyncThrowingStream
      ▼
Core/Auth KeychainStore / ServerStore ── 凭证与多服务器配置
```

- **流式接口**：`command-run`、`node-mirror`、`linux-mirror` 使用 `AsyncThrowingStream<String, Error>` 按行增量返回
- **日志增量**：按 `nextOffset` 递增拉取，`truncated == true` 时重置；客户端缓冲超 2 MB 时截尾保留 1 MB
- **容错解码**：所有面板实体手写 `init(from:)`，逐字段 `try?`，后端新增 / 缺失字段不会导致解码失败

## 二、页面与操作流程

```
启动
 └─ SplashView
     ├─ 无服务器 → ServerListView(onboarding) → ServerEditView（测试连接）→ LoginView
     ├─ 有 Token → MainTabView（乐观进入，后台校验）
     └─ Token 失效 → 强制回 LoginView 并提示
```

### 主界面（4 个 Tab）

| Tab | 页面 | 主要操作 |
| --- | --- | --- |
| 概览 | DashboardView | 面板信息、四项指标、快捷入口、最近运行 |
| 任务 | CronListView → CronDetailView / CronEditView | 筛选（全部/运行中/已启用/已禁用/置顶/订阅）、搜索、标签、运行、停止、启停、置顶、删除、查看实时与历史日志、管理运行实例 |
| 变量 | EnvListView → EnvEditView / EnvDetailView / EnvImportView | 状态筛选、标签、搜索、多选批量（启停 / 标签 / 重命名 / 删除）、值脱敏、导入导出 |
| 更多 | MoreView → 各子页面 | 内容管理 / 面板配置 / 运维工具 / 关于 |

### 关键子流程

**登录**
```
输入账号密码 → [记住密码] → 提交
  ├─ 200 → 保存 Token（Keychain）→ 进入主界面
  ├─ 420 → 弹出两步验证 sheet → 输入 6 位验证码 → 进入
  └─ 面板未初始化 → 弹出初始化 sheet → 设置管理员账号密码
```

**查看实时日志（任务 / 订阅 / 命令通用）**
```
LogConsoleView
  ├─ 打开即拉取末尾 128KB，自动滚底
  ├─ 每 3 秒按 nextOffset 增量追加
  ├─ truncated → 整体重置
  ├─ 可暂停 / 恢复跟随，复制全部 / 分享导出
```

**数据备份**
```
DataBackupView
  ├─ 勾选附加目录（config/scripts/log/syslog/deps/dep_cache/repo/ssh.d/raw/script-history）
  ├─ 导出 → PUT /data/export → tgz 写临时文件 → 系统分享面板
  └─ 导入 → fileImporter 选择 tgz → multipart 上传 → 重载面板生效
```

**命令调试**
```
输入命令（或选预设 / 历史）→ 执行 → 流式输出实时渲染
  ├─ 随时「终止」→ PUT /command-stop
  └─ 历史命令本地保存最近 20 条
```

## 三、构建与打包方案

### 本地（macOS）

```bash
brew install xcodegen ldid
xcodegen generate                                   # 由 project.yml 生成 .xcodeproj
./Scripts/build_ipa.sh                              # 未签名 arm64 → dist/QingLong-<ver>.ipa
```

关键构建参数（Release）：

```
CODE_SIGNING_ALLOWED=NO
CODE_SIGNING_REQUIRED=NO
CODE_SIGN_IDENTITY=""
CODE_SIGN_ENTITLEMENTS=""
DEVELOPMENT_TEAM=""
ARCHS=arm64
```

### IPA 组装

1. 取 `build/Build/Products/Release-iphoneos/QingLong.app`
2. 拷入 `Payload/`
3. `ldid -S` 伪签名（可选，提升 TrollStore 兼容性）
4. 删除 `_CodeSignature/` 与 `embedded.mobileprovision`
5. `zip -qry QingLong.ipa Payload`

CI 会额外校验：`unzip -l` 包结构、`file` 确认 arm64 架构、`plutil -p` 检查版本号与图标键、确认 `Assets.car` 存在。

### CI（GitHub Actions，macos-14 runner）

| 触发 | 行为 |
| --- | --- |
| push `main`/`master` | 构建 + 上传 Artifact（90 天） |
| push tag `v*` | 构建 → 发布 GitHub Release（附 IPA）→ 同步镜像仓库 |
| 手动 `workflow_dispatch` | 可指定 `release_tag` 直接发 Release |
| Pull Request | 仅构建校验 |

版本号规则：tag 时取 `v` 后内容；否则取 `project.yml` 的 `MARKETING_VERSION` + `run_number` 作为 build 号。

### 镜像仓库同步

需要仓库配置：

| 类型 | 名称 | 说明 |
| --- | --- | --- |
| Secret | `MIRROR_TOKEN` | 镜像仓库私人令牌，勾选 `projects` 权限 |
| Variable | `MIRROR_OWNER` | 镜像仓库用户名 / 组织名 |
| Variable | `MIRROR_REPO` | 镜像仓库仓库名 |

未配置时自动跳过，不影响 GitHub 发布。
