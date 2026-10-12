//
//  QLDependence.swift
//  QingLong
//

import Foundation

struct QLDependence: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var type: Int?
    var status: Int?
    var remark: String?
    var log: [String]?
    var timestamp: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        type = try? container.decodeIfPresent(Int.self, forKey: .type)
        status = try? container.decodeIfPresent(Int.self, forKey: .status)
        remark = try? container.decodeIfPresent(String.self, forKey: .remark)
        log = try? container.decodeIfPresent([String].self, forKey: .log)
        timestamp = try? container.decodeIfPresent(String.self, forKey: .timestamp)
    }

    var typeValue: DependenceType { DependenceType(rawValue: type ?? 0) ?? .nodejs }
    var statusValue: DependenceStatus { DependenceStatus(rawValue: status ?? 6) ?? .queued }
    var logText: String { (log ?? []).joined() }
    var isBusy: Bool { statusValue.isBusy }
}

/// 新建依赖请求体
struct DependencePayload: Encodable {
    var id: Int?
    var name: String
    var type: Int
    var remark: String
}

extension Array where Element == QLDependence {
    func search(_ keyword: String) -> [QLDependence] {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return self }
        return filter { $0.name.lowercased().contains(text) }
    }

    func filtered(type: DependenceType?) -> [QLDependence] {
        guard let type else { return self }
        return filter { $0.typeValue == type }
    }

    var busyCount: Int { filter(\.isBusy).count }
}
