//
//  APIClient+Convenience.swift
//  QingLong
//
//  列表 / 空响应等高频形态的语法糖。
//

import Foundation

/// 具备 `{code, message, ...}` 外壳的解码结果
protocol QLCodeChecking {
    var code: Int { get }
    var message: String? { get }
}

extension LogChunk: QLCodeChecking {}
extension QLMessage: QLCodeChecking {}

extension APIClient {

    /// 列表接口。面板在「无数据」时可能返回 `data: null`，这里统一收敛为 `[]`。
    func sendArray<T: Decodable>(
        _ endpoint: Endpoint,
        as element: T.Type = T.self
    ) async throws -> [T] {
        let result: [T]? = try await sendOptional(endpoint, as: [T].self)
        return result ?? []
    }

    /// 解码「非标准外壳」的响应（例如日志接口会在顶层附加分页字段），
    /// 依然校验 code == 200。
    func sendRaw<T: Decodable & QLCodeChecking>(
        _ endpoint: Endpoint,
        as type: T.Type = T.self
    ) async throws -> T {
        let data = try await download(endpoint)
        let value = try JSONCoder.decode(T.self, from: data)
        if value.code == 401 {
            onUnauthorized?()
            throw APIError.unauthorized(value.message)
        }
        guard value.code == 200 else {
            throw APIError.business(code: value.code, message: value.message)
        }
        return value
    }

    /// 只关心成功与否
    func sendVoid(_ endpoint: Endpoint) async throws {
        _ = try await sendMessage(endpoint)
    }

    /// 返回一个 Bool 结果的接口
    func sendBool(_ endpoint: Endpoint) async throws -> Bool {
        let result: Bool? = try await sendOptional(endpoint, as: Bool.self)
        return result ?? true
    }

    /// 返回文本内容（如面板系统日志）
    func sendText(_ endpoint: Endpoint) async throws -> String {
        let data = try await download(endpoint)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
