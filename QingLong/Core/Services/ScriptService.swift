//
//  ScriptService.swift
//  QingLong
//
//  脚本文件管理。所有 `path` 均为相对脚本根目录的路径（空字符串表示根目录）。
//

import Foundation

struct ScriptRenamePayload: Encodable {
    var filename: String
    var path: String
    var newFilename: String
}

struct ScriptDeletePayload: Encodable {
    var filename: String
    var path: String
    var type: String
}

struct ScriptSavePayload: Encodable {
    var filename: String
    var path: String
    var content: String
}

struct ScriptRunPayload: Encodable {
    var filename: String
    var path: String
    var content: String?
}

struct ScriptStopPayload: Encodable {
    var filename: String
    var path: String
    var pid: Int?
}

struct ScriptDirectoryPayload: Encodable {
    var filename: String
    var path: String
    var directory: String
}

struct ScriptFileRefPayload: Encodable {
    var filename: String
    var path: String
}

enum ScriptService {

    private static let basePath = "/api/scripts"

    /// 文件树。`path` 为空时返回以脚本根目录为根的完整嵌套树。
    static func tree(path: String? = nil) async throws -> [QLFileItem] {
        let items = try await APIClient.shared.sendArray(
            Endpoint.get(basePath, query: ["path": path]),
            as: QLFileItem.self
        )
        return items.sortedForDisplay
    }

    /// 读取单个文件内容
    static func content(path: String, file: String) async throws -> String {
        try await APIClient.shared.send(
            Endpoint.get("\(basePath)/detail", query: ["path": path, "file": file]),
            as: String.self
        )
    }

    /// 新建（create = true → POST）或覆盖保存（create = false → PUT）
    static func save(filename: String, path: String, content: String, create: Bool) async throws {
        let payload = ScriptSavePayload(filename: filename, path: path, content: content)
        if create {
            try await APIClient.shared.sendVoid(try Endpoint.post(basePath, body: payload))
        } else {
            try await APIClient.shared.sendVoid(try Endpoint.put(basePath, body: payload))
        }
    }

    /// 新建目录
    static func createDirectory(path: String, directory: String) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.post(
                basePath,
                body: ScriptDirectoryPayload(filename: directory, path: path, directory: directory)
            )
        )
    }

    /// 上传本地文件
    static func upload(path: String, filename: String, data: Data) async throws {
        var form = MultipartFormData()
        form.appendField(name: "filename", value: filename)
        form.appendField(name: "path", value: path)
        form.appendFile(name: "file", filename: filename, data: data)
        try await APIClient.shared.sendVoid(Endpoint.multipart(basePath, form: form))
    }

    static func rename(path: String, filename: String, newFilename: String) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put(
                "\(basePath)/rename",
                body: ScriptRenamePayload(filename: filename, path: path, newFilename: newFilename)
            )
        )
    }

    static func remove(path: String, filename: String, type: String = "file") async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.delete(
                basePath,
                body: ScriptDeletePayload(filename: filename, path: path, type: type)
            )
        )
    }

    static func download(path: String, filename: String) async throws -> Data {
        try await APIClient.shared.download(
            try Endpoint.post(
                "\(basePath)/download",
                body: ScriptFileRefPayload(filename: filename, path: path)
            )
        )
    }

    /// 运行脚本（会把编辑器内的内容写入 `.swap` 临时文件后执行）
    @discardableResult
    static func run(filename: String, path: String, content: String?) async throws -> String? {
        try await APIClient.shared.sendMessage(
            try Endpoint.put(
                "\(basePath)/run",
                body: ScriptRunPayload(filename: filename, path: path, content: content)
            )
        )
    }

    static func stop(filename: String, path: String, pid: Int? = nil) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put(
                "\(basePath)/stop",
                body: ScriptStopPayload(filename: filename, path: path, pid: pid)
            )
        )
    }
}

// MARK: - 文件树工具

enum ScriptFileKind {

    static func symbol(for item: QLFileItem) -> String {
        if item.isDirectory { return "folder.fill" }
        switch item.fileExtension {
        case "js", "mjs", "cjs", "jsx": return "curlybraces"
        case "ts", "tsx": return "curlybraces.square"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "sh", "bash", "zsh": return "terminal"
        case "json": return "list.bullet.rectangle"
        case "md", "txt": return "doc.text"
        case "yml", "yaml", "toml", "ini", "conf", "env": return "gearshape.2"
        case "log": return "doc.plaintext"
        default: return "doc"
        }
    }

    /// 是否是可编辑的文本类脚本
    static func isEditable(_ item: QLFileItem) -> Bool {
        item.isDirectory || !["png", "jpg", "jpeg", "gif", "webp", "zip", "gz", "tgz", "7z", "rar", "pdf", "mp4", "mp3"].contains(item.fileExtension)
    }
}

extension Array where Element == QLFileItem {
    /// 收集所有文件的 key（相对路径）
    var allFileKeys: [String] {
        var result: [String] = []
        for item in self {
            if item.isFile {
                result.append(item.key)
            } else if let children = item.children {
                result.append(contentsOf: children.allFileKeys)
            }
        }
        return result
    }

    /// 过滤出匹配关键字的节点（保留命中的父目录）
    func filtered(keyword: String) -> [QLFileItem] {
        let text = keyword.trimmed.lowercased()
        guard !text.isEmpty else { return self }
        return compactMap { item in
            let children = item.children?.filtered(keyword: keyword) ?? []
            if item.title.lowercased().contains(text) || !children.isEmpty {
                var copy = item
                copy.children = children
                return copy
            }
            return nil
        }
    }
}
