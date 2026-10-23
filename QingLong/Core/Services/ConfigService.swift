//
//  ConfigService.swift
//  QingLong
//
//  配置文件读写。对应后端 `back/api/config.ts`：
//  列表 `GET /api/configs/files`、内容 `GET /api/configs/detail?path=`、
//  保存 `POST /api/configs/save`。
//

import Foundation

struct ConfigSavePayload: Encodable {
    var name: String
    var content: String
}

enum ConfigService {

    private static let base = "/api/configs"

    /// `config/` 目录下的文件清单（面板已过滤掉黑名单文件）
    static func files() async throws -> [QLConfigFile] {
        let items = try await APIClient.shared.sendArray(
            Endpoint.get("\(base)/files", timeout: 20),
            as: QLConfigFile.self
        )
        return items.sortedForDisplay
    }

    /// 读取文件内容。加 `_t` 避免 URL 缓存拿到旧内容。
    static func content(path: String) async throws -> String {
        try await APIClient.shared.send(
            Endpoint.get(
                "\(base)/detail",
                query: ["path": path, "_t": String(Int(Date().timeIntervalSince1970))],
                timeout: 40
            ),
            as: String.self
        )
    }

    static func save(name: String, content: String) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.post("\(base)/save", body: ConfigSavePayload(name: name, content: content))
        )
    }
}
