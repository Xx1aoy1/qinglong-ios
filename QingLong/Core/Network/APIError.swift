//
//  APIError.swift
//  QingLong
//
//  统一的网络 / 业务错误类型。
//

import Foundation

enum APIError: LocalizedError, Equatable {
    /// 尚未配置服务器地址
    case notConfigured
    /// 地址非法
    case invalidURL(String)
    /// 未登录 / Token 失效（HTTP 401 或业务 code 401）
    case unauthorized(String?)
    /// 业务层返回的失败 code（非 200）
    case business(code: Int, message: String?)
    /// HTTP 层错误
    case http(status: Int, message: String?)
    /// 响应体解析失败
    case decoding(String)
    /// 传输层错误（超时、断网、证书等）
    case network(String)
    /// 取消
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "尚未配置青龙面板地址"
        case .invalidURL(let value):
            return "面板地址无效：\(value)"
        case .unauthorized(let message):
            return message?.isEmpty == false ? message! : "登录已失效，请重新登录"
        case .business(let code, let message):
            if let message, !message.isEmpty { return message }
            return "请求失败（code \(code)）"
        case .http(let status, let message):
            if let message, !message.isEmpty { return message }
            switch status {
            case 403: return "没有权限访问该资源"
            case 404: return "接口不存在，请确认青龙面板版本"
            case 502, 503, 504: return "面板暂时不可用（HTTP \(status)）"
            default: return "服务器返回异常（HTTP \(status)）"
            }
        case .decoding(let detail):
            #if DEBUG
            return "数据解析失败：\(detail)"
            #else
            return "数据解析失败，可能面板版本不兼容"
            #endif
        case .network(let detail):
            return detail
        case .cancelled:
            return "请求已取消"
        case .unknown(let detail):
            return detail
        }
    }

    /// 是否属于「需要重新登录」的错误
    var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    /// 是否属于「可以直接重试」的临时性错误
    var isRetryable: Bool {
        switch self {
        case .network: return true
        case .http(let status, _): return status >= 500
        default: return false
        }
    }
}
