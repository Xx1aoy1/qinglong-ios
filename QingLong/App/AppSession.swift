//
//  AppSession.swift
//  QingLong
//
//  全局会话：服务器列表、当前连接、登录态、用户信息、全局提示。
//  所有页面都通过 `@EnvironmentObject` 拿到它。
//

import Foundation
import SwiftUI

@MainActor
final class AppSession: ObservableObject {

    // MARK: - 状态

    enum Phase: Equatable {
        /// 启动中
        case booting
        /// 还没有任何服务器
        case needsServer
        /// 有服务器但未登录
        case needsLogin
        /// 已登录
        case ready

        var isReady: Bool { self == .ready }
    }

    @Published private(set) var phase: Phase = .booting
    @Published private(set) var servers: [ServerConfig] = []
    @Published private(set) var activeServer: ServerConfig?
    @Published private(set) var user: QLUser?
    @Published private(set) var systemStatus: SystemStatus?
    @Published var toast: ToastMessage?

    /// 登录失败的重试次数（面板侧限制）
    @Published private(set) var lastLoginFailure: String?

    private let store = ServerStore()

    /// 是否记住密码（默认关闭，仅保存在系统钥匙串）
    var rememberPassword: Bool {
        get { UserDefaults.standard.bool(forKey: "ql.rememberPassword") }
        set { UserDefaults.standard.set(newValue, forKey: "ql.rememberPassword") }
    }

    // MARK: - 初始化

    init() {
        APIClient.shared.onUnauthorized = { [weak self] in
            Task { @MainActor in
                self?.forceLogout(reason: "登录已失效，请重新登录")
            }
        }
    }

    // MARK: - 启动流程

    func bootstrap() async {
        servers = store.servers
        guard !servers.isEmpty else {
            phase = .needsServer
            return
        }

        let target = store.find(store.activeServerID) ?? servers[0]
        guard let token = KeychainStore.token(for: target.id), !token.isEmpty else {
            activeServer = target
            store.activeServerID = target.id
            APIClient.shared.configure(baseURL: target.baseURL, token: nil)
            phase = .needsLogin
            return
        }

        activate(server: target, token: token)
        // 先乐观进入，再后台校验 Token 是否仍然有效
        phase = .ready
        await refreshAll()
    }

    private func activate(server: ServerConfig, token: String?) {
        activeServer = server
        store.activeServerID = server.id
        APIClient.shared.configure(baseURL: server.baseURL, token: token)
    }

    // MARK: - 服务器管理

    /// 探测地址并保存（不登录）
    @discardableResult
    func addOrUpdateServer(id: UUID? = nil, address: String, alias: String) async throws -> ServerConfig {
        guard let url = ServerConfig.normalize(address) else {
            throw APIError.invalidURL(address)
        }
        // 连通性 + 版本探测
        let status = try await APIClient.shared.probe(baseURL: url)

        var server = id.flatMap { store.find($0) }
            ?? ServerConfig(id: id ?? UUID(), alias: alias, address: url.absoluteString)
        server.alias = alias
        server.address = url.absoluteString
        store.upsert(server)
        servers = store.servers
        systemStatus = status
        return server
    }

    func deleteServer(_ server: ServerConfig) {
        store.remove(server)
        servers = store.servers
        if activeServer?.id == server.id {
            activeServer = nil
            APIClient.shared.configure(baseURL: nil, token: nil)
            user = nil
            phase = servers.isEmpty ? .needsServer : .needsLogin
        }
    }

    /// 切换当前服务器（会清空运行态，回到登录页）
    func switchTo(server: ServerConfig) {
        let token = KeychainStore.token(for: server.id)
        activate(server: server, token: token)
        user = nil
        systemStatus = nil
        ListCache.clear()
        if let token, !token.isEmpty {
            phase = .ready
            Task { await refreshAll() }
        } else {
            phase = .needsLogin
        }
    }

    /// 连接前探测（添加服务器 / 修改地址时使用）
    func probe(address: String) async throws -> SystemStatus {
        guard let url = ServerConfig.normalize(address) else {
            throw APIError.invalidURL(address)
        }
        return try await APIClient.shared.probe(baseURL: url)
    }

    // MARK: - 登录 / 登出

    enum LoginOutcome: Equatable {
        case success
        case needsTwoFactor
    }

    func login(username: String, password: String) async throws -> LoginOutcome {
        guard let server = activeServer ?? servers.first else {
            throw APIError.notConfigured
        }
        activate(server: server, token: nil)
        lastLoginFailure = nil

        let response = try await UserService.login(username: username, password: password)
        switch response.code {
        case LoginCode.success:
            guard let token = response.data?.token, !token.isEmpty else {
                throw APIError.decoding("登录成功但未返回 Token")
            }
            finishLogin(server: server, username: username, password: password, token: token)
            return .success
        case LoginCode.needTwoFactor:
            return .needsTwoFactor
        default:
            let message = response.message ?? "登录失败"
            lastLoginFailure = message
            throw APIError.business(code: response.code, message: message)
        }
    }

    func verifyTwoFactor(username: String, password: String, code: String) async throws {
        guard let server = activeServer ?? servers.first else {
            throw APIError.notConfigured
        }
        activate(server: server, token: nil)
        let response = try await UserService.twoFactorLogin(
            username: username,
            password: password,
            code: code
        )
        guard response.code == LoginCode.success, let token = response.data?.token else {
            let message = response.message ?? "验证码校验失败"
            lastLoginFailure = message
            throw APIError.business(code: response.code, message: message)
        }
        finishLogin(server: server, username: username, password: password, token: token)
    }

    /// 面板仍处于默认账号时初始化管理员
    func initialize(username: String, password: String) async throws {
        guard let server = activeServer ?? servers.first else {
            throw APIError.notConfigured
        }
        APIClient.shared.configure(baseURL: server.baseURL, token: nil)
        let message = try await UserService.initialize(username: username, password: password)
        showToast(message ?? "初始化成功", tone: .success)
    }

    private func finishLogin(server: ServerConfig, username: String, password: String, token: String) {
        KeychainStore.saveToken(token, for: server.id)
        if rememberPassword {
            try? KeychainStore.set(password, for: "password.\(server.id.uuidString)")
        } else {
            KeychainStore.remove("password.\(server.id.uuidString)")
        }

        var updated = server
        updated.username = username
        updated.lastConnectedAt = Date()
        store.upsert(updated)
        servers = store.servers

        activate(server: updated, token: token)
        phase = .ready
        lastLoginFailure = nil
    }

    func savedPassword(for server: ServerConfig) -> String? {
        guard rememberPassword else { return nil }
        return KeychainStore.get("password.\(server.id.uuidString)")
    }

    func logout() {
        Task {
            try? await UserService.logout()
        }
        if let server = activeServer {
            KeychainStore.removeToken(for: server.id)
        }
        APIClient.shared.setToken(nil)
        ListCache.clear()
        user = nil
        phase = servers.isEmpty ? .needsServer : .needsLogin
        showToast("已退出登录", tone: .info)
    }

    /// Token 失效时由 APIClient 回调
    private func forceLogout(reason: String) {
        guard phase == .ready else { return }
        if let server = activeServer {
            KeychainStore.removeToken(for: server.id)
        }
        APIClient.shared.setToken(nil)
        ListCache.clear()
        user = nil
        phase = servers.isEmpty ? .needsServer : .needsLogin
        showToast(reason, tone: .warning)
    }

    // MARK: - 刷新

    func refreshAll() async {
        async let userTask: Void = fetchUser()
        async let statusTask: Void = fetchSystemStatus()
        _ = await (userTask, statusTask)
    }

    private func fetchUser() async {
        do {
            user = try await UserService.currentUser()
        } catch {
            handle(error)
        }
    }

    private func fetchSystemStatus() async {
        do {
            systemStatus = try await UserService.systemStatus()
        } catch {
            // 面板信息获取失败不阻断使用
            #if DEBUG
            print("system status error: \(error)")
            #endif
        }
    }

    /// 手动刷新面板信息（登录页判断是否需要初始化时使用）
    func refreshSystemStatus() async {
        await fetchSystemStatus()
    }

    // MARK: - 统一错误处理

    /// 在 ViewModel 里统一用它把错误转成用户可读的提示
    func handle(_ error: Error) {
        let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
        if apiError == .cancelled { return }
        if apiError.isUnauthorized {
            forceLogout(reason: apiError.localizedDescription)
            return
        }
        showToast(apiError.localizedDescription, tone: .danger)
    }

    func showToast(_ text: String, tone: ToastMessage.Tone = .info) {
        withAnimation(.easeOut(duration: 0.2)) {
            toast = ToastMessage(text: text, tone: tone)
        }
        let current = toast
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if toast?.id == current?.id {
                withAnimation(.easeIn(duration: 0.2)) { toast = nil }
            }
        }
    }
}

// MARK: - Toast

struct ToastMessage: Identifiable, Equatable {
    enum Tone {
        case info, success, warning, danger

        var color: Color {
            switch self {
            case .info: return Theme.info
            case .success: return Theme.success
            case .warning: return Theme.warning
            case .danger: return Theme.danger
            }
        }

        var symbol: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .danger: return "xmark.octagon.fill"
            }
        }
    }

    let id = UUID()
    var text: String
    var tone: Tone
}
