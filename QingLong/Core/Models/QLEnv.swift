//
//  QLEnv.swift
//  QingLong
//
//  环境变量。对应后端 `back/data/env.ts`。
//

import Foundation

struct QLEnv: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var value: String
    var remarks: String?
    var status: Int?
    var position: Int?
    var isPinned: Int?
    var labels: [String]?
    var timestamp: String?

    enum CodingKeys: String, CodingKey {
        case id, name, value, remarks, status, position, isPinned, labels, timestamp
    }

    init(
        id: Int,
        name: String,
        value: String,
        remarks: String? = nil,
        status: Int? = 0,
        position: Int? = nil,
        isPinned: Int? = 0,
        labels: [String]? = nil,
        timestamp: String? = nil
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.remarks = remarks
        self.status = status
        self.position = position
        self.isPinned = isPinned
        self.labels = labels
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        value = (try? container.decode(String.self, forKey: .value)) ?? ""
        remarks = try? container.decodeIfPresent(String.self, forKey: .remarks)
        status = try? container.decodeIfPresent(Int.self, forKey: .status)
        position = try? container.decodeIfPresent(Int.self, forKey: .position)
        isPinned = try? container.decodeIfPresent(Int.self, forKey: .isPinned)
        labels = try? container.decodeIfPresent([String].self, forKey: .labels)
        timestamp = try? container.decodeIfPresent(String.self, forKey: .timestamp)
    }

    var isDisabled: Bool { status == EnvStatus.disabled.rawValue }
    var isPinnedValue: Bool { isPinned == 1 }
    var statusValue: EnvStatus { EnvStatus(rawValue: status ?? 0) ?? .normal }
    var labelList: [String] { labels ?? [] }

    /// 列表里展示的脱敏值（长值截断）
    var maskedValue: String {
        if value.count <= 24 { return value }
        return String(value.prefix(12)) + "…" + String(value.suffix(6))
    }

    var hasVisibleValue: Bool { !value.isEmpty }
}

/// 新建环境变量的请求体（同时用于 JSON 导入 / 导出）
struct EnvCreatePayload: Codable {
    var name: String
    var value: String
    var remarks: String
    var labels: [String]

    init(name: String, value: String, remarks: String = "", labels: [String] = []) {
        self.name = name
        self.value = value
        self.remarks = remarks
        self.labels = labels
    }
}

/// 更新环境变量的请求体
struct EnvUpdatePayload: Encodable {
    var id: Int
    var name: String
    var value: String
    var remarks: String
    var labels: [String]
}

/// 批量改名的请求体
struct EnvRenamePayload: Encodable {
    var ids: [Int]
    var name: String
}

/// 标签增删的请求体
struct LabelPayload: Encodable {
    var ids: [Int]
    var labels: [String]
}

/// 排序请求体
struct MovePayload: Encodable {
    var fromIndex: Int
    var toIndex: Int
}

extension Array where Element == QLEnv {
    var allLabels: [String] {
        var result = Set<String>()
        for env in self {
            result.formUnion(env.labelList)
        }
        return result.sorted()
    }

    func search(_ keyword: String) -> [QLEnv] {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return self }
        return filter { env in
            env.name.lowercased().contains(text)
                || env.value.lowercased().contains(text)
                || (env.remarks ?? "").lowercased().contains(text)
                || env.labelList.contains { $0.lowercased().contains(text) }
        }
    }
}
