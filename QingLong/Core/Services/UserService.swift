//
//  UserService.swift
//  QingLong
//
//  登录、账号、两步验证、通知设置。
//

import Foundation

enum UserService {

    /// 面板信息（白名单接口，无需 Token）
    static func systemStatus() async throws -> SystemStatus {
        try await APIClient.shared.send(Endpoint.get("/api/system", requiresAuth: false))
    }

    /// 账号密码登录。返回 (code, data)：
    /// - code == 200 → data.token 可用
    /// - code == 420 → 开启了两步验证，需调用 `twoFactorLogin`
    static func login(username: String, password: String) async throws -> QLResponse<LoginResult> {
        let endpoint = try Endpoint.post(
            "/api/user/login",
            body: LoginRequest(username: username, password: password),
            requiresAuth: false
        )
        return try await APIClient.shared.sendEnvelope(endpoint, as: LoginResult.self)
    }

    /// 两步验证登录
    static func twoFactorLogin(username: String, password: String, code: String) async throws -> QLResponse<LoginResult> {
        let endpoint = try Endpoint.put(
            "/api/user/two-factor/login",
            body: TwoFactorLoginRequest(username: username, password: password, code: code),
            requiresAuth: false
        )
        return try await APIClient.shared.sendEnvelope(endpoint, as: LoginResult.self)
    }

    /// 首次初始化面板账号（仅当面板仍为默认 admin/admin 时可用）
    static func initialize(username: String, password: String) async throws -> String? {
        let endpoint = try Endpoint.put(
            "/api/user/init",
            body: LoginRequest(username: username, password: password),
            requiresAuth: false
        )
        return try await APIClient.shared.sendMessage(endpoint)
    }

    static func logout() async throws {
        try await APIClient.shared.sendMessage(Endpoint.post("/api/user/logout", body: EmptyPayload()))
    }

    /// 当前登录用户信息
    static func currentUser() async throws -> QLUser {
        try await APIClient.shared.send(Endpoint.get("/api/user"), as: QLUser.self)
    }

    /// 修改用户名 / 密码（会失效所有已登录会话）
    static func updateAccount(username: String, password: String) async throws -> String? {
        try await APIClient.shared.sendMessage(
            Endpoint.put("/api/user", body: LoginRequest(username: username, password: password))
        )
    }

    static func loginLog() async throws -> [LoginLogItem] {
        let result: [LoginLogItem]? = try await APIClient.shared.sendOptional(
            Endpoint.get("/api/user/login-log"),
            as: [LoginLogItem].self
        )
        return result ?? []
    }

    // MARK: - 两步验证

    static func twoFactorSetup() async throws -> TwoFactorSetup {
        try await APIClient.shared.send(Endpoint.get("/api/user/two-factor/init"), as: TwoFactorSetup.self)
    }

    static func activateTwoFactor(code: String) async throws {
        try await APIClient.shared.sendMessage(
            Endpoint.put("/api/user/two-factor/active", body: TwoFactorCodeRequest(code: code))
        )
    }

    static func deactivateTwoFactor() async throws {
        try await APIClient.shared.sendMessage(
            Endpoint.put("/api/user/two-factor/deactivate", body: EmptyPayload())
        )
    }

    // MARK: - 通知设置

    /// 读取通知配置（返回的是扁平对象）
    static func notificationSettings() async throws -> NotificationSettings {
        try await APIClient.shared.send(Endpoint.get("/api/user/notification"), as: NotificationSettings.self)
    }

    /// 保存通知配置。面板会**立即发送一条测试通知**，失败时抛 `.business(code: 400)`。
    static func saveNotificationSettings(_ settings: NotificationSettings) async throws {
        try await APIClient.shared.sendMessage(
            Endpoint.put("/api/user/notification", body: settings)
        )
    }

    // MARK: - 安全：IP 黑名单

    static func ipBlacklist() async throws -> [String] {
        try await APIClient.shared.sendArray(Endpoint.get("/api/user/ip-blacklist"), as: String.self)
    }

    @discardableResult
    static func blockIp(_ ip: String) async throws -> [String] {
        try await APIClient.shared.sendArray(
            try Endpoint.put("/api/user/ip-blacklist", body: IpPayload(ip: ip)),
            as: String.self
        )
    }

    @discardableResult
    static func unblockIp(_ ip: String) async throws -> [String] {
        try await APIClient.shared.sendArray(
            try Endpoint.delete("/api/user/ip-blacklist", body: IpPayload(ip: ip)),
            as: String.self
        )
    }

    // MARK: - 开放接口应用令牌

    /// 用 openApp 的 client_id / client_secret 换取 Token（`GET /open/auth/token`）
    static func appToken(clientID: String, clientSecret: String) async throws -> String? {
        let response: QLResponse<OpenAuthToken> = try await APIClient.shared.sendEnvelope(
            Endpoint.get(
                "/api/auth/token",
                query: ["client_id": clientID, "client_secret": clientSecret],
                requiresAuth: false
            ),
            as: OpenAuthToken.self
        )
        guard response.isSuccess else {
            throw APIError.business(code: response.code, message: response.message)
        }
        return response.data?.token
    }
}

struct OpenAuthToken: Codable {
    var token: String?
    var expiration: Int?
}

// MARK: - 请求体

struct LoginRequest: Encodable {
    var username: String
    var password: String
}

struct TwoFactorLoginRequest: Encodable {
    var username: String
    var password: String
    var code: String
}

struct TwoFactorCodeRequest: Encodable {
    var code: String
}

struct IpPayload: Encodable {
    var ip: String
}

struct AuthResetRequest: Encodable {
    var username: String?
    var password: String?
    var retries: Int?
    var twoFactorActivated: Bool?
}
