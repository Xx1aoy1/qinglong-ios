//
//  APIClient.swift
//  QingLong
//
//  与青龙面板通信的统一入口。
//
//  设计要点
//  --------
//  1. 面板所有接口都是 `{ code, message, data }` 外壳，code == 200 视为成功；
//  2. 鉴权使用 `Authorization: Bearer <jwt>`，JWT 由 `/api/user/login` 下发；
//  3. 面板后端会根据 User-Agent 判定平台（`getPlatform()`），
//     iOS 客户端必须让 UA 命中 `ios|iphone|ipad|ipod`，
//     这样 Token 才会被归入 mobile 平台槽位（面板默认每平台最多 10 个 Token）。
//  4. `/open/*` 与 `/api/*` 在后端是同一套路由（`rewrite('/open/*','/api/$1')`），
//     本客户端统一使用 `/api/*`。
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

final class APIClient {

    static let shared = APIClient()

    // MARK: - 连接上下文

    private let lock = NSLock()
    private var _baseURL: URL?
    private var _token: String?

    /// Token 失效时回调（由 AppSession 注册，用于强制回到登录页）
    var onUnauthorized: (() -> Void)?

    var baseURL: URL? {
        lock.lock(); defer { lock.unlock() }
        return _baseURL
    }

    var token: String? {
        lock.lock(); defer { lock.unlock() }
        return _token
    }

    func configure(baseURL: URL?, token: String?) {
        lock.lock()
        let baseChanged = _baseURL != baseURL
        _baseURL = baseURL
        if token != nil || baseChanged {
            _token = token
        }
        lock.unlock()
    }

    func setToken(_ token: String?) {
        lock.lock()
        _token = token
        lock.unlock()
    }

    // MARK: - URLSession

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        self.session = URLSession(configuration: configuration)
    }

    /// 自定义 URLSession（用于单元测试或特殊超时场景）
    static func makeSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = max(timeout, 300)
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    // MARK: - 请求构造

    static var userAgent: String {
        #if canImport(UIKit)
        let version = UIDevice.current.systemVersion
        let model = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        let model = "iPhone"
        #endif
        return "QingLong-iOS/\(AppInfo.version) (\(model); iOS \(version)) Mobile/15E148"
    }

    private func makeRequest(_ endpoint: Endpoint) throws -> URLRequest {
        guard let base = baseURL else { throw APIError.notConfigured }

        let raw = base.absoluteString + endpoint.path
        guard var components = URLComponents(string: raw) else {
            throw APIError.invalidURL(raw)
        }

        let items = endpoint.query
            .compactMap { key, value -> URLQueryItem? in
                guard let value else { return nil }
                return URLQueryItem(name: key, value: value)
            }
            .sorted { $0.name < $1.name }

        if !items.isEmpty {
            var existing = components.queryItems ?? []
            existing.append(contentsOf: items)
            components.queryItems = existing
        }

        guard let url = components.url else {
            throw APIError.invalidURL(raw)
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = endpoint.timeout ?? 30

        if let contentType = endpoint.contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let body = endpoint.body {
            request.httpBody = body
        }
        if endpoint.requiresAuth, let token = token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    // MARK: - 传输

    private func transport(_ endpoint: Endpoint) async throws -> (Data, HTTPURLResponse) {
        let request: URLRequest
        do {
            request = try makeRequest(endpoint)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.unknown(error.localizedDescription)
        }

        #if DEBUG
        NetworkLog.request(request)
        #endif

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw APIError.cancelled }
            throw APIError.network(Self.friendlyMessage(for: error))
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            throw APIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("服务器返回了无法识别的响应")
        }

        #if DEBUG
        NetworkLog.response(http, data: data)
        #endif

        if http.statusCode == 401 {
            onUnauthorized?()
            let message = Self.extractMessage(from: data)
            throw APIError.unauthorized(message)
        }

        return (data, http)
    }

    // MARK: - 解码

    /// 在后台线程解码。
    ///
    /// `/api/dependencies` 这类接口一次会返回数 MB（后端把每条依赖的完整安装日志
    /// 一起返回），如果在主线程上解码，几 MB 的 JSON 足以造成明显掉帧甚至卡死。
    /// 所有响应统一走这里解码。
    static func decodeOffMain<T: Decodable>(_ type: T.Type, from data: Data) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                // JSONDecoder 不是线程安全的，这里用独立实例，
                // 避免与主线程共用的 JSONCoder.decoder 互相干扰。
                let decoder = JSONDecoder()
                do {
                    continuation.resume(returning: try decoder.decode(type, from: data))
                } catch let error as DecodingError {
                    continuation.resume(throwing: APIError.decoding(JSONCoder.describe(error)))
                } catch {
                    continuation.resume(throwing: APIError.decoding(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - 高层 API

    /// 解码外壳但不做业务 code 校验（供登录等需要读取特殊 code 的场景使用）
    func sendEnvelope<T: Decodable>(
        _ endpoint: Endpoint,
        as type: T.Type = T.self
    ) async throws -> QLResponse<T> {
        let (data, _) = try await transport(endpoint)
        return try await Self.decodeOffMain(QLResponse<T>.self, from: data)
    }

    /// 要求 code == 200 且返回 data
    @discardableResult
    func send<T: Decodable>(
        _ endpoint: Endpoint,
        as type: T.Type = T.self
    ) async throws -> T {
        let envelope = try await sendEnvelope(endpoint, as: T.self)
        if envelope.code == 401 {
            onUnauthorized?()
            throw APIError.unauthorized(envelope.message)
        }
        return try envelope.requireData()
    }

    /// data 允许为 null 的场景
    @discardableResult
    func sendOptional<T: Decodable>(
        _ endpoint: Endpoint,
        as type: T.Type = T.self
    ) async throws -> T? {
        let envelope = try await sendEnvelope(endpoint, as: T.self)
        if envelope.code == 401 {
            onUnauthorized?()
            throw APIError.unauthorized(envelope.message)
        }
        guard envelope.isSuccess else {
            throw APIError.business(code: envelope.code, message: envelope.message)
        }
        return envelope.data
    }

    /// 只关心成功与否，返回面板的提示文案
    @discardableResult
    func sendMessage(_ endpoint: Endpoint) async throws -> String? {
        let (data, _) = try await transport(endpoint)
        let envelope = try await Self.decodeOffMain(QLMessage.self, from: data)
        if envelope.code == 401 {
            onUnauthorized?()
            throw APIError.unauthorized(envelope.message)
        }
        guard envelope.isSuccess else {
            throw APIError.business(code: envelope.code, message: envelope.message)
        }
        return envelope.message
    }

    /// 下载原始字节（脚本 / 日志下载、数据导出）
    func download(_ endpoint: Endpoint) async throws -> Data {
        let (data, http) = try await transport(endpoint)

        // 出错时后端会返回 JSON 而不是文件；正常文件（脚本 / 日志）可能很大，
        // 所以只在响应体很小时才尝试按 JSON 解析。
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.contains("application/json"),
           data.count < 262_144,
           let envelope = try? JSONCoder.decode(QLMessage.self, from: data),
           !envelope.isSuccess {
            throw APIError.business(code: envelope.code, message: envelope.message)
        }
        return data
    }

    /// 流式文本（`/api/system/command-run` 的实时输出）
    func streamText(_ endpoint: Endpoint) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(endpoint)
                    #if DEBUG
                    NetworkLog.request(request)
                    #endif
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw APIError.network("无法识别的响应")
                    }
                    if http.statusCode == 401 {
                        onUnauthorized?()
                        throw APIError.unauthorized("登录已失效，请重新登录")
                    }
                    if http.statusCode >= 400 {
                        throw APIError.http(status: http.statusCode, message: nil)
                    }

                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as APIError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: APIError.network(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 连通性探测

    /// 探测面板是否可达、是否需要初始化（`/api/system` 在白名单内，无需 Token）
    func probe(baseURL: URL) async throws -> SystemStatus {
        let previousBase = self.baseURL
        let previousToken = self.token
        configure(baseURL: baseURL, token: nil)
        defer { configure(baseURL: previousBase, token: previousToken) }

        let endpoint = Endpoint.get("/api/system", requiresAuth: false)
        let (data, _) = try await transport(endpoint)
        let envelope = try JSONCoder.decode(QLResponse<SystemStatus>.self, from: data)
        guard envelope.isSuccess, let status = envelope.data else {
            throw APIError.business(code: envelope.code, message: envelope.message)
        }
        return status
    }

    // MARK: - 工具

    private static func extractMessage(from data: Data) -> String? {
        (try? JSONCoder.decode(QLMessage.self, from: data))?.message
    }

    private static func friendlyMessage(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet: return "设备未连接网络"
        case .cannotFindHost: return "找不到主机，请检查面板地址是否正确"
        case .cannotConnectToHost: return "无法连接到面板，请确认地址与端口、以及服务是否已启动"
        case .timedOut: return "连接超时，请检查网络或面板负载"
        case .networkConnectionLost: return "网络连接已断开"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return "HTTPS 证书校验失败（自签证书面板可改用 http 访问）"
        case .appTransportSecurityRequiresSecureConnection:
            return "被系统 ATS 策略拦截，请使用 http 或配置证书"
        default: return error.localizedDescription
        }
    }
}

// MARK: - 调试日志

#if DEBUG
enum NetworkLog {
    static func request(_ request: URLRequest) {
        print("→ \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")")
        if let token = request.value(forHTTPHeaderField: "Authorization") {
            print("  Authorization: \(token.prefix(24))…")
        }
        if let body = request.httpBody, let text = String(data: body, encoding: .utf8) {
            print("  body: \(text.count > 600 ? String(text.prefix(600)) + "…" : text)")
        }
    }

    static func response(_ response: HTTPURLResponse, data: Data) {
        print("← \(response.statusCode) (\(data.count) bytes)")
        if let text = String(data: data, encoding: .utf8) {
            print("  \(text.count > 600 ? String(text.prefix(600)) + "…" : text)")
        }
    }
}
#endif
