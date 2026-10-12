//
//  ServerConfig.swift
//  QingLong
//
//  一台青龙面板的配置。支持多实例并存、快速切换。
//

import Foundation

struct ServerConfig: Identifiable, Codable, Equatable {
    var id: UUID
    /// 备注名，例如「家里的群晖」
    var alias: String
    /// 用户输入的原始地址，例如 192.168.1.10:5700 或 https://ql.example.com
    var address: String
    /// 便于回显的登录用户名（密码与 Token 不落地到这里）
    var username: String?
    var lastConnectedAt: Date?

    init(
        id: UUID = UUID(),
        alias: String = "",
        address: String,
        username: String? = nil,
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.alias = alias
        self.address = address
        self.username = username
        self.lastConnectedAt = lastConnectedAt
    }

    var displayName: String {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (baseURL?.absoluteString ?? address) : trimmed
    }

    var baseURL: URL? { Self.normalize(address) }

    var hostDescription: String {
        guard let url = baseURL else { return address }
        return url.absoluteString
    }

    // MARK: - 地址归一化

    /// 把用户输入的各种写法统一成可直接拼接 `/api/xxx` 的根地址。
    ///
    /// 支持：
    /// - `192.168.1.10:5700`            → `http://192.168.1.10:5700`
    /// - `http://192.168.1.10:5700/`    → `http://192.168.1.10:5700`
    /// - `https://ql.example.com/api`   → `https://ql.example.com`
    /// - `ql.example.com/ql/`           → `http://ql.example.com/ql`
    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // 去掉用户可能粘贴进来的「打开面板」链接中的多余部分
        if let hashIndex = text.firstIndex(of: "#") {
            text = String(text[text.startIndex..<hashIndex])
        }
        if !text.contains("://") {
            text = "http://" + text
        }

        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.trimmingCharacters(in: .whitespaces),
              !host.isEmpty else {
            return nil
        }

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        // 允许用户把 /api 一起粘进来，但客户端自己会补 /api
        if path.lowercased().hasSuffix("/api") {
            path = String(path.dropLast(4))
        }
        while path.hasSuffix("/") { path.removeLast() }

        components.path = path
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil

        if let port = components.port, port <= 0 || port > 65535 { return nil }
        return components.url
    }

    /// 校验并返回错误提示（nil 表示合法）
    static func validate(address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "请输入面板地址" }
        if normalize(trimmed) == nil {
            return "地址格式不正确，例如：192.168.1.10:5700 或 https://ql.example.com"
        }
        return nil
    }
}

// MARK: - 持久化

final class ServerStore {

    private enum Keys {
        static let servers = "ql.servers"
        static let activeServerID = "ql.activeServerID"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var servers: [ServerConfig] {
        get {
            guard let data = defaults.data(forKey: Keys.servers) else { return [] }
            return (try? decoder.decode([ServerConfig].self, from: data)) ?? []
        }
        set {
            let data = try? encoder.encode(newValue)
            defaults.set(data, forKey: Keys.servers)
        }
    }

    var activeServerID: UUID? {
        get {
            guard let raw = defaults.string(forKey: Keys.activeServerID) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            if let newValue {
                defaults.set(newValue.uuidString, forKey: Keys.activeServerID)
            } else {
                defaults.removeObject(forKey: Keys.activeServerID)
            }
        }
    }

    func upsert(_ server: ServerConfig) {
        var list = servers
        if let index = list.firstIndex(where: { $0.id == server.id }) {
            list[index] = server
        } else {
            list.append(server)
        }
        servers = list
    }

    func remove(_ server: ServerConfig) {
        servers = servers.filter { $0.id != server.id }
        KeychainStore.removeToken(for: server.id)
        if activeServerID == server.id {
            activeServerID = nil
        }
    }

    func find(_ id: UUID?) -> ServerConfig? {
        guard let id else { return nil }
        return servers.first { $0.id == id }
    }
}
