//
//  DependenceService.swift
//  QingLong
//

import Foundation

enum DependenceService {

    private static let basePath = "/api/dependencies"

    static func list(
        searchValue: String? = nil,
        type: DependenceType? = nil,
        status: String? = nil
    ) async throws -> [QLDependence] {
        try await APIClient.shared.sendArray(
            Endpoint.get(
                basePath,
                query: [
                    "searchValue": searchValue,
                    "type": type.map { String($0.rawValue) },
                    "status": status
                ]
            ),
            as: QLDependence.self
        )
    }

    /// 批量新建（面板接口接收数组）
    static func create(_ payloads: [DependencePayload]) async throws {
        try await APIClient.shared.sendVoid(try Endpoint.post(basePath, body: payloads))
    }

    static func create(name: String, type: DependenceType, remark: String = "") async throws {
        try await create([DependencePayload(id: nil, name: name, type: type.rawValue, remark: remark)])
    }

    static func update(_ payload: DependencePayload) async throws {
        try await APIClient.shared.sendVoid(try Endpoint.put(basePath, body: payload))
    }

    static func remove(ids: [Int], force: Bool = false) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.delete("\(basePath)\(force ? "/force" : "")", body: ids)
        )
    }

    static func reinstall(ids: [Int]) async throws {
        try await APIClient.shared.sendVoid(try Endpoint.put("\(basePath)/reinstall", body: ids))
    }

    static func cancel(ids: [Int]) async throws {
        try await APIClient.shared.sendVoid(try Endpoint.put("\(basePath)/cancel", body: ids))
    }

    static func detail(id: Int) async throws -> QLDependence {
        try await APIClient.shared.send(Endpoint.get("\(basePath)/\(id)"), as: QLDependence.self)
    }
}
