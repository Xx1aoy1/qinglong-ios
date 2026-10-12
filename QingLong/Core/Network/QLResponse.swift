//
//  QLResponse.swift
//  QingLong
//
//  青龙面板统一响应外壳：{ "code": 200, "message": "...", "data": ... }
//

import Foundation

struct QLResponse<D: Decodable>: Decodable {
    let code: Int
    let message: String?
    let data: D?

    var isSuccess: Bool { code == 200 }

    func requireData() throws -> D {
        guard isSuccess else {
            throw APIError.business(code: code, message: message)
        }
        guard let data else {
            throw APIError.decoding("响应缺少 data 字段")
        }
        return data
    }
}

/// 只关心成功与否的响应用它解码，避免 `QLResponse<Empty>` 的泛型噪音。
struct QLMessage: Decodable {
    let code: Int
    let message: String?

    var isSuccess: Bool { code == 200 }
}

/// 空请求体（`POST`/`PUT` 需要 body 但面板不校验内容时使用）
struct EmptyPayload: Codable {}

/// `/api/logs/detail`、`/api/crons/:id/log` 等日志接口会在顶层额外返回分页字段。
struct LogChunk: Decodable {
    let code: Int
    let message: String?
    let data: String?
    let logStatus: String?
    let offset: Int?
    let nextOffset: Int?
    let total: Int?
    let truncated: Bool?

    var isSuccess: Bool { code == 200 }
    var content: String { data ?? "" }
    var isRunning: Bool { logStatus == "running" }
}

/// 两步验证已开启时，登录接口返回 code = 420，提示客户端进入验证码输入。
enum LoginCode {
    static let success = 200
    static let needTwoFactor = 420
    static let badCredentials = 400
    static let tooManyAttempts = 410
    static let notInitialized = 450
}
