//
//  LogService.swift
//  QingLong
//
//  面板日志文件浏览。`GET /api/logs` 返回的是**嵌套文件树**，
//  节点 `key` 相对日志根目录，`parent` 为上级相对路径。
//

import Foundation

enum LogService {

    /// 日志文件树
    static func tree() async throws -> [QLFileItem] {
        let items = try await APIClient.shared.sendArray(
            Endpoint.get("/api/logs"),
            as: QLFileItem.self
        )
        return items.sortedForDisplay
    }

    /// 读取日志分片
    static func detail(
        path: String,
        file: String,
        offset: Int? = nil,
        limit: Int? = nil,
        tail: Bool? = nil
    ) async throws -> LogChunk {
        let endpoint = Endpoint.get(
            "/api/logs/detail",
            query: [
                "path": path,
                "file": file,
                "offset": offset.map(String.init),
                "limit": limit.map(String.init),
                "tail": tail.map { $0 ? "true" : "false" },
                "_t": String(Int(Date().timeIntervalSince1970))
            ]
        )
        return try await APIClient.shared.sendRaw(endpoint, as: LogChunk.self)
    }

    static func remove(path: String, filename: String, type: String? = "file") async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.delete(
                "/api/logs",
                body: LogDeletePayload(filename: filename, path: path, type: type)
            )
        )
    }

    /// 下载原文件（返回二进制）
    static func download(path: String, filename: String) async throws -> Data {
        try await APIClient.shared.download(
            try Endpoint.post(
                "/api/logs/download",
                body: LogDeletePayload(filename: filename, path: path, type: "file")
            )
        )
    }
}

struct LogDeletePayload: Encodable {
    var filename: String
    var path: String
    var type: String?
}

extension Array where Element == QLFileItem {
    /// 在嵌套树里按 key 深度优先查找
    func findNode(key: String) -> QLFileItem? {
        for item in self {
            if item.key == key { return item }
            if let found = item.children?.findNode(key: key) { return found }
        }
        return nil
    }

    /// 统计树中的文件数量
    var fileCountRecursive: Int {
        reduce(0) { partial, item in
            item.isFile ? partial + 1 : partial + (item.children?.fileCountRecursive ?? 0)
        }
    }
}
