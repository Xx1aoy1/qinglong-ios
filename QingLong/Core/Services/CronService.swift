//
//  CronService.swift
//  QingLong
//

import Foundation

/// `/api/crons/:id/logs` 返回的历史日志文件
struct CronLogFile: Codable, Identifiable, Hashable {
    var filename: String
    var directory: String?
    var time: Double?

    var id: String { "\(directory ?? "")/\(filename)" }

    var timeDescription: String {
        guard let time, time > 0 else { return "" }
        return Date(timeIntervalSince1970: time / 1000).absoluteDescription
    }
}

/// `/api/crons/:id/instances`
struct CronInstanceInfo: Codable, Identifiable, Hashable {
    var id: Int
    var cron_id: Int?
    var status: Int?
    var pid: Int?
    var started_at: Double?
    var finished_at: Double?
    var exit_code: Int?
    var log_path: String?

    var isRunning: Bool { finished_at == nil || (finished_at ?? 0) == 0 }

    var startedText: String {
        guard let started_at, started_at > 0 else { return "—" }
        return Date(timeIntervalSince1970: started_at / 1000).absoluteDescription
    }
}

/// `GET /api/crons` 的列表外壳。
/// 青龙 2.22+ 返回分页对象 `{ data: [...], total: n }`，更早版本返回纯数组，
/// 这里两种形态都兼容。
struct CronListPage: Decodable {
    let data: [QLCron]
    let total: Int?

    private enum CodingKeys: String, CodingKey { case data, total }

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let list = try? single.decode([QLCron].self) {
            data = list
            total = list.count
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = (try? container.decode([QLCron].self, forKey: .data)) ?? []
        total = try? container.decodeIfPresent(Int.self, forKey: .total)
    }
}

enum CronService {

    private static let path = "/api/crons"

    static func list(searchValue: String? = nil) async throws -> [QLCron] {
        let page = try await APIClient.shared.send(
            Endpoint.get(path, query: ["searchValue": searchValue]),
            as: CronListPage.self
        )
        return page.data
    }

    static func detail(id: Int) async throws -> QLCron {
        try await APIClient.shared.send(Endpoint.get("\(path)/\(id)"), as: QLCron.self)
    }

    static func create(_ payload: CronPayload) async throws {
        try await APIClient.shared.sendVoid(try Endpoint.post(path, body: payload))
    }

    static func update(_ payload: CronPayload) async throws {
        try await APIClient.shared.sendVoid(try Endpoint.put(path, body: payload))
    }

    static func remove(ids: [Int]) async throws {
        try await APIClient.shared.sendVoid(try Endpoint.delete(path, body: ids))
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

    static func setPinned(ids: [Int], pinned: Bool) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put("\(path)/\(pinned ? "pin" : "unpin")", body: ids)
        )
    }

    static func addLabels(ids: [Int], labels: [String]) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.post("\(path)/labels", body: LabelPayload(ids: ids, labels: labels))
        )
    }

    static func removeLabels(ids: [Int], labels: [String]) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.delete("\(path)/labels", body: LabelPayload(ids: ids, labels: labels))
        )
    }

    // MARK: - 日志

    /// 读取任务日志分片。`tail: true` 时返回文件末尾内容。
    static func log(
        id: Int,
        offset: Int? = nil,
        limit: Int? = nil,
        tail: Bool? = nil
    ) async throws -> LogChunk {
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

    /// 历史日志文件列表
    static func logFiles(id: Int) async throws -> [CronLogFile] {
        try await APIClient.shared.sendArray(
            Endpoint.get("\(path)/\(id)/logs"),
            as: CronLogFile.self
        )
    }

    /// 运行实例（多实例场景）
    static func instances(id: Int) async throws -> [CronInstanceInfo] {
        try await APIClient.shared.sendArray(
            Endpoint.get("\(path)/\(id)/instances"),
            as: CronInstanceInfo.self
        )
    }

    static func stopInstance(cronID: Int, instanceID: Int) async throws {
        try await APIClient.shared.sendVoid(
            Endpoint.post("\(path)/\(cronID)/instances/\(instanceID)/stop", body: EmptyPayload())
        )
    }
}
