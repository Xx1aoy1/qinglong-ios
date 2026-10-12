# 青龙助手 iOS（qinglong-ios）· 项目长期约定

## 仓库与发布
- 仓库：https://github.com/Xx1aoy1/qinglong-ios （账号 Xx1aoy1，token 权限 repo + workflow）
- **仓库内任何文件与提交信息都只提 GitHub，不出现其他代码托管平台的名称**（用户 2026-10-12 明确要求）
- 发布方式：推 `v*` tag → CI（`build` + `release` 两个 job）自动构建未签名 arm64 IPA 并创建 GitHub Release
- 产物目标：TrollStore（巨魔）安装，无需任何证书

## 工程约定
- XcodeGen 管理，`project.yml` 是唯一事实来源；`.xcodeproj` 入 `.gitignore`，不手工编辑
- 最低 iOS 15.0，SwiftUI，零第三方依赖
- Release 构建强制未签名：`CODE_SIGNING_ALLOWED=NO`
- 所有 ViewModel 为 `@MainActor final class` + `@StateObject`
- 面板实体一律手写容错 `init(from:)`（`try?` 逐字段），防后端字段缺失导致整页崩溃

## 环境限制（务必注意）
- 本机为 Windows，无 Swift/Xcode 工具链 → 编译正确性只能靠 CI 验证
- 沙箱内 **`github.com` 不可达，仅 `api.github.com` 可达** → `git push/fetch` 会失败
  - 推送改用 GitHub **Git Data API**（blobs → trees → commits → PATCH ref）建提交
  - 本地与远端 commit sha 会不一致，但 tree 相同；正常网络下用 `git fetch && git reset --hard origin/main` 对齐
- 工具输出渲染层可能把 `String` 显示成假字符串（曾出现 `Vfjxct`）→ 判断源码问题必须做字节级核验，不能按显示内容改代码
- 临时脚本一律放仓库外（`%TEMP%`），`git add -A` 曾把含 token 的脚本提交，被 GitHub push protection 拦下（GH013）
- 沙箱代理端口会变（见过 5605 / 3469）。`objects.githubusercontent.com` 可达但**间歇性 502**，下载 Release 资产要带重试；下载走 `GET /repos/{o}/{r}/releases/assets/{id}` + `Accept: application/octet-stream`
- `api.github.com` 未鉴权会 403 限流，任何请求都要带 token
- `Read`/部分 `Grep`/`Bash` 会随机返回 `SENSITIVE_APPROVAL=TIMED_OUT`（重试常成功）→ 用简单 pattern 的精准 Grep 代替整文件 Read，最终以 CI 结果为准

## 性能约定（列表页）
- 列表页派生数据（过滤结果 / 标签集合 / 各筛选计数）必须**一次算完并缓存**，禁止在 `body` 里写会重复计算的计算属性
- 输入类过滤一律加防抖（现为 180ms）
- 页面进入用 `loadIfStale(maxAge:)`，切 Tab 不重复请求；**有过期缓存时走 `load(silent: true)`**，不要整页闪 loading
- 新增列表页应复用 `ListCache`（`QingLong/Core/App/ListCache.swift`）做**内存 + 磁盘**缓存：`init()` 先命中缓存再后台刷新；用 `ListCache.lastLoaded(.xxx)` 判断新鲜度（不要用 ViewModel 实例属性存时间戳，换页面就丢了）；切换服务器/退出登录时清空
- 行内标签不要用 `WrapHStack`（FlowLayout 每行都要测量）→ 用单行 `HStack` + 前 N 个 + `+N` 溢出
- 首次加载时**筛选栏/title 先渲染**，只在内容区域转圈（`content` = filterBar + contentBody 两段）
- 有缓存内容时请求失败只弹 Toast，不要把整页换成错误页
- 轮询类刷新空闲时降频（≥15s），只在 busy 时密集轮询

## 已知的重接口（面板侧，改不动）
- `GET /api/dependencies`：返回体含**每条依赖的完整安装日志**（`DependenceModel.findAll()` 带 `log` JSON 列，单条可达 MB），且每次请求都 `refreshInstalledStatuses()` 逐条跑 shell 探测（并发 5）→ 秒级耗时、响应数 MB。客户端策略：缓存 5 分钟、静默刷新、落盘前剥掉 `log`、超时放宽到 60s。
- 所有响应一律经 `APIClient.decodeOffMain` 在后台队列解码（数 MB JSON 在主线程解码会卡死）；该函数用**独立 JSONDecoder 实例**，因为 `JSONCoder.decoder` 是共享静态实例、非线程安全。

## 显示层陷阱（务必牢记）
- `String` 在某些工具输出里会被**替换显示**成 `Vfjxct`（CI 能编译过即证明是假象）。**绝不能按显示内容改代码**，必须 `open(p,'rb')` 做字节扫描确认。


