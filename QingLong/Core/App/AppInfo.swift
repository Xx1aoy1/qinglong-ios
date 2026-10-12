//
//  AppInfo.swift
//  QingLong
//

import Foundation

enum AppInfo {
    static let displayName = "青龙助手"

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.qinglong.mobile"
    }

    static var versionDescription: String {
        "\(version) (\(build))"
    }

    /// 面板接口前缀，青龙固定为 /api
    static let apiPrefix = "/api"

    /// 上游青龙面板项目
    static let upstreamURL = URL(string: "https://github.com/whyour/qinglong")!

    /// 本客户端仓库地址。
    /// 由构建时注入（Info.plist 的 `QLRepositoryURL`，CI 会按当前仓库自动填充）。
    static var clientRepositoryURL: URL? { infoURL(for: "QLRepositoryURL") }

    /// 兼容旧引用：默认指向客户端仓库（缺失时回退到上游项目）
    static var repositoryURL: URL {
        clientRepositoryURL ?? upstreamURL
    }

    private static func infoURL(for key: String) -> URL? {
        guard let raw = Bundle.main.infoDictionary?[key] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return URL(string: trimmed)
    }
}

/// 应用级常量
enum AppDefaults {
    static let accentHex = "#12B7A8"
    /// 环境变量列表的分页大小（面板接口一次性返回全部，这里只用于本地渐进渲染）
    static let listPageSize = 50
}
