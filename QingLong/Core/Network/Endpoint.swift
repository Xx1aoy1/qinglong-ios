//
//  Endpoint.swift
//  QingLong
//
//  接口描述：路径 + 方法 + 查询参数 + 请求体。
//

import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

struct Endpoint {
    var path: String
    var method: HTTPMethod = .get
    var query: [String: String?] = [:]
    var body: Data?
    var contentType: String?
    /// 该接口是否需要携带 Token（登录 / 初始化接口不需要）
    var requiresAuth: Bool = true
    /// 覆盖默认超时
    var timeout: TimeInterval?

    init(
        path: String,
        method: HTTPMethod = .get,
        query: [String: String?] = [:],
        body: Data? = nil,
        contentType: String? = nil,
        requiresAuth: Bool = true,
        timeout: TimeInterval? = nil
    ) {
        self.path = path
        self.method = method
        self.query = query
        self.body = body
        self.contentType = contentType
        self.requiresAuth = requiresAuth
        self.timeout = timeout
    }
}

// MARK: - 便捷构造

extension Endpoint {
    static func get(
        _ path: String,
        query: [String: String?] = [:],
        requiresAuth: Bool = true,
        timeout: TimeInterval? = nil
    ) -> Endpoint {
        Endpoint(
            path: path,
            method: .get,
            query: query,
            requiresAuth: requiresAuth,
            timeout: timeout
        )
    }

    static func post<T: Encodable>(
        _ path: String,
        body: T,
        requiresAuth: Bool = true
    ) throws -> Endpoint {
        Endpoint(
            path: path,
            method: .post,
            body: try JSONCoder.encode(body),
            contentType: "application/json",
            requiresAuth: requiresAuth
        )
    }

    static func put<T: Encodable>(
        _ path: String,
        body: T? = nil,
        query: [String: String?] = [:],
        requiresAuth: Bool = true
    ) throws -> Endpoint {
        Endpoint(
            path: path,
            method: .put,
            query: query,
            body: try body.map { try JSONCoder.encode($0) },
            contentType: body == nil ? nil : "application/json",
            requiresAuth: requiresAuth
        )
    }

    static func delete<T: Encodable>(
        _ path: String,
        body: T? = nil,
        query: [String: String?] = [:]
    ) throws -> Endpoint {
        Endpoint(
            path: path,
            method: .delete,
            query: query,
            body: try body.map { try JSONCoder.encode($0) },
            contentType: body == nil ? nil : "application/json"
        )
    }

    /// 表单（application/x-www-form-urlencoded）
    static func form(_ path: String, method: HTTPMethod = .post, fields: [String: String]) -> Endpoint {
        var components = URLComponents()
        components.queryItems = fields
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        let string = components.percentEncodedQuery ?? ""
        return Endpoint(
            path: path,
            method: method,
            body: string.data(using: .utf8),
            contentType: "application/x-www-form-urlencoded"
        )
    }

    /// multipart/form-data
    static func multipart(
        _ path: String,
        method: HTTPMethod = .post,
        form: MultipartFormData
    ) -> Endpoint {
        Endpoint(
            path: path,
            method: method,
            body: form.finalize(),
            contentType: "multipart/form-data; boundary=\(form.boundary)"
        )
    }
}

// MARK: - JSON 编解码器

enum JSONCoder {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw APIError.decoding("请求体编码失败：\(error.localizedDescription)")
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch let error as DecodingError {
            throw APIError.decoding(Self.describe(error))
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    /// 把 `DecodingError` 转成带字段路径的中文说明（也供后台线程解码复用）
    static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "缺少字段 `\(key.stringValue)`（\(context.codingPath.map(\.stringValue).joined(separator: "."))）"
        case .typeMismatch(let type, let context):
            return "字段类型不匹配，期望 \(type)（\(context.codingPath.map(\.stringValue).joined(separator: "."))）"
        case .valueNotFound(let type, let context):
            return "字段值为空，期望 \(type)（\(context.codingPath.map(\.stringValue).joined(separator: "."))）"
        case .dataCorrupted(let context):
            return "数据损坏：\(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}
