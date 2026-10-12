//
//  SubscriptionService.swift
//  QingLong
//

import Foundation

enum SubscriptionService {

    private static let path = "/api/subscriptions"

    static func list(searchValue: String? = nil) async throws -> [QLSubscription] {
        try await APIClient.shared.sendArray(
            Endpoint.get(path, query: ["searchValue": searchValue]),
            as: QLSubscription.self
        )
    }

    static func create(_ payload: SubscriptionPayload) async throws {
        try await APIClient.shared.sendVoid(try Endpoint.post(path, body: payload))
    }

    static func update(_ payload: SubscriptionPayload) async throws {
        try await APIClient.shared.sendVoid(try Endpoint.put(path, body: payload))
    }

    static func remove(ids: [Int], force: Bool = false) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.delete(path, body: ids, query: ["force": force ? "true" : nil])
        )
    }

    static func run(ids: [Int]) async throws {
        try await APIClient.shared.sendVoid(try Endpoint.put("\(path)/run", body: ids))
    }

    static func stop(ids: [Int]) async throws {
        try await APIClient.shared.sendVoid(try Endpoint.put("\(path)/stop", body: ids))
    }

    static func setEnabled(ids: [Int], enabled: Bool) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put("\(path)/\(enabled ? "enable" : "disable")", body: ids)
        )
    }

    static func log(id: Int, offset: Int? = nil, limit: Int? = nil, tail: Bool? = nil) async throws -> LogChunk {
        let endpoint = Endpoint.get(
            "\(path)/\(id)/log",
            query: [
                "offset": offset.map(String.init),
                "limit": limit.map(String.init),
                "tail": tail.map { $0 ? "true" : "false" },
                "_t": String(Int(Date().timeIntervalSince1970))
            ]
        )
        return try await APIClient.shared.sendRaw(endpoint, as: LogChunk.self)
    }

    static func logFiles(id: Int) async throws -> [CronLogFile] {
        try await APIClient.shared.sendArray(Endpoint.get("\(path)/\(id)/logs"), as: CronLogFile.self)
    }
}
