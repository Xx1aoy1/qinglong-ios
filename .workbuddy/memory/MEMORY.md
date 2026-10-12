# 青龙助手 iOS（qinglong-ios）· 项目长期约定

## 仓库与发布
- 仓库：https://github.com/Xx1aoy1/qinglong-ios （账号 Xx1aoy1，token 权限 repo + workflow）
- **只发布到 GitHub，不引入镜像仓库或任何其他镜像渠道**（用户 2026-10-12 明确要求）
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
