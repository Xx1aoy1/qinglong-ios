//
//  CronViewService.swift
//  QingLong
//
//  定时任务视图（`/api/crons/views`）。面板 2.19+ 才提供，旧版本会返回 404。
//

import Foundation

/// 创建 / 更新视图的请求体。
/// 后端 Joi 校验不允许多余字段，所以 `id` 只在编辑时出现（`nil` 会被编码器省略）。
struct CronViewPayload: Encodable {
    var id: Int?
    var name: String
    var filters: [CronViewFilter]
    var sorts: [CronViewSort]
    var filterRelation: String
}

enum CronViewService {

    private static let path = "/api/crons/views"

    static func list() async throws -> [QLCronView] {
        try await APIClient.shared.sendArray(Endpoint.get(path), as: QLCronView.self)
    }

    static func create(
        name: String,
        filters: [CronViewFilter],
        sorts: [CronViewSort],
        relation: String
    ) async throws {
        let payload = CronViewPayload(
            id: nil,
            name: name,
            filters: filters,
            sorts: sorts,
            filterRelation: relation
        )
        try await APIClient.shared.sendVoid(try Endpoint.post(path, body: payload))
    }

    static func update(
        id: Int,
        name: String,
        filters: [CronViewFilter],
        sorts: [CronViewSort],
        relation: String
    ) async throws {
        let payload = CronViewPayload(
            id: id,
            name: name,
            filters: filters,
            sorts: sorts,
            filterRelation: relation
        )
        try await APIClient.shared.sendVoid(try Endpoint.put(path, body: payload))
    }

    static func remove(ids: [Int]) async throws {
        try await APIClient.shared.sendVoid(try Endpoint.delete(path, body: ids))
    }

    static func setEnabled(ids: [Int], enabled: Bool) async throws {
        let endpoint = try Endpoint.put("\(path)/\(enabled ? "enable" : "disable")", body: ids)
        try await APIClient.shared.sendVoid(endpoint)
    }

    static func move(id: Int, from: Int, to: Int) async throws {
        let endpoint = try Endpoint.put(
            "\(path)/move",
            body: CronViewMovePayload(id: id, fromIndex: from, toIndex: to)
        )
        try await APIClient.shared.sendVoid(endpoint)
    }
}

struct CronViewMovePayload: Encodable {
    var id: Int
    var fromIndex: Int
    var toIndex: Int
}
