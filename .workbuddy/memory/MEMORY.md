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
  - **API 创建的 commit 对象结尾不带换行**（内容是「头 + 空行 + message」），而真实 `git commit` 的 message 后带一个 `\n` → 两种途径即使内容等价，**SHA 也永远不同**。拿 API 返回的 `message` 重建对象时必须「补换行 / 不补换行」两种变体都试，取 SHA 吻合的那个。`POST /git/tags` 同理
  - 对齐本地用「**物化**」法：`GET /git/trees/{sha}`（**非递归**，字段是 `path` 不是 `name`）拿全 tree/blob → `git hash-object -t blob -w --stdin` 写 blob → `git mktree` **自底向上**写 tree → `git hash-object -t commit -w --stdin` 写 commit → `git update-ref refs/heads/main` / `refs/tags/*` → `git reset`。可把本地 SHA 拉到与远端**逐字节一致**，彻底消除分叉
- 提交身份统一为 `Xx1aoy1 <151541726+Xx1aoy1@users.noreply.github.com>`；**任何提交的作者/提交者邮箱都不得含其他托管平台的域名**（曾因 `git config` 里的旧邮箱把平台名带进全部 14 个提交头）
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

## 日志分片接口的 `truncated` 语义（踩过坑，务必牢记）
- 后端 `back/shared/logReader.ts`：`truncated: offset > 0 || nextOffset < total` —— 它表示**「本次分片未覆盖整个文件」**，**不是**「日志被轮转」。
- 客户端增量轮询追平文件末尾后（`offset == total`），`offset > 0` 恒成立 → `truncated` 恒为 `true`。
- 因此**绝不能**用 `truncated` 判断轮转并清空已读内容（曾导致实时日志看几秒后整页变「暂无日志内容」）。
- 正确的轮转判定：`chunk.total < nextOffset`（文件比已读位置还小）时才静默重取尾部 `fetch(nil, chunkSize, true)`。
- 任务日志 / 订阅日志 / 面板日志共用 `LogConsoleView`，改一处即可全覆盖。

## 面板接口对照（已核实，勿猜）
- **配置文件**：`GET /api/configs/files`、`GET /api/configs/detail?path=`、`POST /api/configs/save {name, content}`。
  旧的 `/api/config/file` 与 `GET /api/configs/:file` 已下线（410），不要再接。
- **任务视图**：`GET/POST/PUT/DELETE /api/crons/views`、`PUT /views/enable|disable`（body 为 `[id]`）、`PUT /views/move`。
  `filters: [{property, operation, value}]`（Reg/NotReg/In/Nin），`sorts: [{type, value}]`（字段名是 `value`），
  `type == 1` 为内置视图不可改名删除。面板查询走 `queryString`，**客户端改为本地求值**以便复用列表缓存。

## 运维提示
- GitHub token 会轮换；失效时所有 API 返回 **401 Bad credentials**（区别于 403 限流）。此时向用户索取新 token，并把 `%TEMP%/ql_*.py` 里的旧 token 批量替换即可继续。**不要把 token 写进仓库或记忆文件。**

## 显示层陷阱（务必牢记）
- `String` 在某些工具输出里会被**替换显示**成 `Vfjxct`（CI 能编译过即证明是假象）。**绝不能按显示内容改代码**，必须 `open(p,'rb')` 做字节扫描确认。

## 文本编辑一律用 CodeEditorView（勿再用 TextEditor）
- SwiftUI `TextEditor` 绑定长文本时，每敲一键都会把整段文本回写底层 `UITextView`，`selectedRange` / `contentOffset` 被重置 → 「删一个字符光标就跳走、找不回位置」。文本越长越明显。
- 统一用 `QingLong/Design/CodeEditorView.swift`（`UIViewRepresentable` + `UITextView`）。
- **只包 UITextView 还不够（1.0.6 就栽在这）**：只要在 `updateUIView` 里每次更新都重设 `textColor` / `font` / `isEditable` / `textContainerInset`，`UITextView` 的 setter 会重建文本属性并把 `selectedRange` 顶到末尾 —— 照样跳。**这些外观属性只能在「真的变了」时设置**（`Coordinator` 缓存上次的 scheme/font/insets/editable，比较后再设，且设完把 selectedRange 放回去）。纯输入路径一个 setter 都不许碰。
- 第二道保险：编辑文本**不要用 `@Published`**。改为 `private(set) var content` + `var textBinding: Binding<String>{ Binding(get:set:) }`，输入只更新 `isDirty`（仅翻转时通知）+ 220ms 防抖的 `charCount`。这样输入过程完全不触发 SwiftUI 重算，`updateUIView` 根本不会被调用。
- 编辑类页面 `load()` 必须做幂等（`loadedPath` / `loadedKey` + `force`），否则重复 appear 会把编辑框内容顶回服务器版本。
- 仍在用裸 `TextEditor` 的地方（CronEditView 命令、EnvEditView、SystemConfigView SSH key、CommandRunnerView）都是短文本，暂未替换。




