<div align="center">

<img src="docs/icon.png" width="96" alt="青龙助手图标" />

# 青龙助手 QingLong for iOS

**青龙面板（QingLong）的第三方 iOS 客户端 · SwiftUI 原生实现 · 未签名 IPA 适配 TrollStore**

[![Build Unsigned IPA](https://github.com/Xx1aoy1/qinglong-ios/actions/workflows/build-ipa.yml/badge.svg)](../../actions/workflows/build-ipa.yml)
![iOS](https://img.shields.io/badge/iOS-15.0%2B-0FA894)
![Swift](https://img.shields.io/badge/Swift-5.5%2B-F05138)
![License](https://img.shields.io/badge/License-MIT-2BD4BC)
![Dependencies](https://img.shields.io/badge/third--party%20deps-0-12B7A8)

</div>

---

## 项目简介

「青龙助手」是一个从零编写的开源 iOS 客户端，用于在 iPhone / iPad 上管理你自建的 [青龙面板](https://github.com/whyour/qinglong)。

- **零第三方依赖**：全部基于系统框架（SwiftUI / Security / UIKit），不引入任何包管理器
- **最低 iOS 15.0**：同时适配 iPhone 与 iPad，自动适配深色模式
- **未签名 IPA**：CI 直接产出 `.ipa`，配合 [TrollStore（巨魔）](https://github.com/opa334/TrollStore) 安装即用，**无需任何开发者证书**
- **直连面板**：所有数据都来自你自己部署的面板，客户端不经过任何中转服务器

## 功能一览

| 模块 | 能力 |
| --- | --- |
| 🏠 概览 | 面板状态、任务 / 变量 / 订阅 / 依赖数量、最近运行、快捷入口 |
| ⏰ 定时任务 | 列表筛选（运行中 / 已启用 / 已禁用 / 置顶 / 订阅来源）、运行与停止、启停与置顶、创建与编辑（cron / `@once` / `@boot`、标签、前置后置命令、多实例、工作目录）、实时日志增量跟随、历史日志、运行实例管理 |
| 📦 环境变量 | 增删改查、启用禁用、标签、置顶、排序、批量操作、JSON / `name=value` 导入导出、值脱敏显示 |
| 🔄 订阅管理 | 新建（公开仓库 / 私有仓库 / 单文件）、crontab 与固定间隔两种调度、黑白名单、手动拉取与停止、拉取日志 |
| 📜 脚本管理 | 目录树浏览、在线编辑保存、直接运行脚本并查看输出、新建文件 / 文件夹、重命名、上传、下载、删除 |
| 🧩 依赖管理 | NodeJS / Python3 / Linux 三类依赖的安装、重装、卸载、取消，安装日志实时跟踪 |
| 🗂 日志浏览 | 按目录浏览面板全部日志文件，复制 / 分享 / 导出 |
| ⚙️ 面板设置 | 面板标题、语言、时区、日志保留天数、任务并发、依赖代理、Node / Python / Linux 镜像源（流式输出）、SSH 私钥、清理依赖缓存、重载面板、检查更新 |
| 🔔 通知设置 | 内置 **22 种通知渠道** 的完整字段配置（Server酱、Bark、PushDeer、Telegram、钉钉、企业微信、飞书、gotify、ntfy、pushplus…），保存即测试 |
| 🔐 账号安全 | 修改用户名密码、两步验证（TOTP 初始化 / 激活 / 解绑）、登录日志、IP 黑名单 |
| 🔗 开放接口 | 开放应用与密钥管理（client_id / client_secret / scopes / 重置密钥） |
| 🛠 运维工具 | 命令调试（流式输出 + 历史命令）、数据备份与还原（tgz 导入导出）、面板系统日志 |
| 🖥 多服务器 | 同时保存多个面板地址，一键切换，凭证分别存于系统钥匙串 |

## 安装

### 前置条件

设备需已安装 **TrollStore（巨魔）**。本应用以未签名 IPA 分发，TrollStore 会在安装时自动签名，**请勿**使用 AltStore / Sideloadly 等需要证书的工具。

### 获取 IPA

前往 [Releases](../../releases) 页面下载最新 `QingLong-<version>.ipa`。

### 安装步骤

1. 将 IPA 传输到设备（AirDrop / 文件 App / 爱思助手 / Filza 均可）
2. 打开 **TrollStore** → 点击 `+` → 选择该 IPA → **Install**
3. 启动「青龙助手」，添加面板地址（如 `http://192.168.1.10:5700`）并登录
4. 首次启动如提示本地网络权限，请允许（访问内网面板需要）

> 应用已默认放开 ATS 限制，HTTP 地址与自签证书的面板均可直连。

## 从源码构建

### macOS 本地构建

```bash
# 依赖
brew install xcodegen ldid

# 构建（未签名 / arm64）
./Scripts/build_ipa.sh
# 或指定版本
VERSION=1.0.0 ./Scripts/build_ipa.sh

# 产物
# dist/QingLong-1.0.0.ipa
```

### GitHub Actions 自动构建

仓库自带工作流 [.github/workflows/build-ipa.yml](.github/workflows/build-ipa.yml)：

| 触发方式 | 行为 |
| --- | --- |
| push 到 `main` / `master` | 构建未签名 IPA，上传为 Artifact（保留 90 天） |
| push tag `v*`（如 `v1.0.0`） | 构建 → 校验包结构 → 创建 GitHub Release 并附 IPA |
| 手动触发（`workflow_dispatch`） | 填写 `release_tag` 可直接发 Release，留空则仅产出 Artifact |
| Pull Request | 只构建校验，不发布 |

> 工程使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 管理，`project.yml` 是唯一事实来源，`.xcodeproj` 已加入 `.gitignore`，不要手工编辑或提交。

### 重新生成应用图标

```bash
pip install pillow
python Scripts/generate_assets.py
```

## 发布

推一个 `v*` 形式的 tag 即可自动发布，无需任何证书或额外配置：

```bash
git tag -a v1.0.0 -m "青龙助手 iOS 1.0.0"
git push origin v1.0.0
```

CI 会完成构建 → 校验包结构 → 创建 GitHub Release 并附上 `QingLong-<version>.ipa`。

## 项目结构

```
.
├── project.yml                     # XcodeGen 工程定义（唯一事实来源）
├── Support/
│   ├── Info.plist
│   └── QingLong.entitlements
├── QingLong/
│   ├── App/                        # 应用入口与全局会话
│   │   ├── QingLongApp.swift
│   │   ├── RootView.swift
│   │   └── AppSession.swift        # 登录态 / 多服务器 / Toast
│   ├── Core/
│   │   ├── App/                    # AppInfo / DateFormatting
│   │   ├── Auth/                   # KeychainStore / ServerConfig
│   │   ├── Models/                 # 全部数据模型（容错解码）
│   │   ├── Network/                # APIClient / Endpoint / QLResponse / Multipart
│   │   └── Services/               # 7 个业务 Service（对齐面板 146 条路由）
│   ├── Components/                 # 状态胶囊 / 空态 / 加载 / Toast / 输入弹窗
│   ├── Design/                     # 设计令牌 Theme / 色彩 / 修饰符
│   ├── Features/
│   │   ├── Server/                 # 服务器列表与编辑
│   │   ├── Login/                  # 登录 / 两步验证 / 面板初始化
│   │   ├── Main/                   # 主 TabView
│   │   ├── Dashboard/              # 概览
│   │   ├── Crons/                  # 任务列表 / 详情 / 编辑
│   │   ├── Envs/                   # 变量列表 / 编辑 / 详情 / 导入
│   │   ├── Subscriptions/          # 订阅列表 / 编辑 / 详情
│   │   ├── Scripts/                # 脚本浏览 / 在线编辑器
│   │   ├── Dependencies/           # 依赖管理
│   │   ├── Logs/                   # 日志控制台 / 日志浏览器
│   │   └── Settings/               # 面板设置 / 通知 / 账号安全 / 开放接口 / 命令调试 / 数据备份 / 系统日志 / 关于
│   └── Resources/
│       └── Assets.xcassets         # AppIcon / AccentColor / LaunchBackground
├── Scripts/
│   ├── build_ipa.sh                # macOS 一键构建
│   └── generate_assets.py          # 图标生成
├── .github/workflows/build-ipa.yml # CI：构建 / 校验 / 发布
└── LICENSE                         # MIT
```

## 技术要点

- **认证**：`POST /api/user/login` 获取 JWT，`Authorization: Bearer` 携带；凭证保存在 `kSecClassGenericPassword` 钥匙串中
- **平台槽位**：面板按 User-Agent 区分 `mobile` / `desktop` Token 槽位（每槽位上限 10 个），客户端 UA 固定含 `iOS`，确保归入 mobile
- **统一响应外壳**：`{ code, message?, data? }`，`code == 200` 视为成功；日志类接口在顶层额外返回 `logStatus / offset / nextOffset / total / truncated`，由 `sendRaw` 统一处理
- **流式输出**：`/api/system/command-run` 等接口用 `AsyncThrowingStream` 按行增量渲染
- **容错解码**：所有面板实体均手写 `init(from:)` 逐字段 `try?` 容错，后端字段缺失不会导致整页崩溃
- **日志增量跟随**：按 `nextOffset` 递增拉取，`truncated` 时自动重置，超过 2 MB 自动截尾保留 1 MB，控制内存占用
- **iOS 15 兼容**：`FlowLayout` 加 `@available(iOS 16)` 分支；所有 `alert` + `TextField` 场景使用自研 `PromptSheet` 组件替代

## 与官方的关系

本项目是青龙面板的**第三方客户端**，与 [whyour/qinglong](https://github.com/whyour/qinglong) 官方及其作者无任何隶属、合作或背书关系。应用内所有数据均来自你自己部署的面板服务，客户端不收集、不上传任何账号信息。

## License

[MIT](LICENSE)
