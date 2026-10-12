//
//  QLFileItem.swift
//  QingLong
//
//  面板返回的通用文件树节点（脚本、日志共用 `IFile` 结构）。
//

import Foundation

struct QLFileItem: Codable, Identifiable, Hashable {
    var title: String
    var key: String
    var type: String
    var parent: String?
    var createTime: Int?
    var size: Int?
    var children: [QLFileItem]?

    var id: String { key.isEmpty ? title : key }
    var isDirectory: Bool { type == "directory" }
    var isFile: Bool { !isDirectory }

    var fileExtension: String {
        (title as NSString).pathExtension.lowercased()
    }

    var sizeText: String {
        guard let size, size > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    var createTimeText: String {
        guard let createTime, createTime > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(createTime) / 1000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// 根目录节点（用于日志浏览里没有 children 的扁平列表）
    var pathComponents: [String] {
        key.split(separator: "/").map(String.init)
    }
}

extension Array where Element == QLFileItem {
    /// 把面板返回的扁平数组（仅根层）按目录优先、名称排序
    var sortedForDisplay: [QLFileItem] {
        sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }
}
