//
//  EnvService.swift
//  QingLong
//

import Foundation

enum EnvService {

    private static let path = "/api/envs"

    static func list(searchValue: String? = nil) async throws -> [QLEnv] {
        try await APIClient.shared.sendArray(
            Endpoint.get(path, query: ["searchValue": searchValue]),
            as: QLEnv.self
        )
    }

    /// 批量新建（面板接口本身接收数组）
    @discardableResult
    static func create(_ payloads: [EnvCreatePayload]) async throws -> [QLEnv] {
        let endpoint = try Endpoint.post(path, body: payloads)
        let result: [QLEnv]? = try await APIClient.shared.sendOptional(endpoint, as: [QLEnv].self)
        return result ?? []
    }

    @discardableResult
    static func create(name: String, value: String, remarks: String, labels: [String]) async throws -> [QLEnv] {
        try await create([EnvCreatePayload(name: name, value: value, remarks: remarks, labels: labels)])
    }

    static func update(_ payload: EnvUpdatePayload) async throws {
        try await APIClient.shared.sendVoid(try Endpoint.put(path, body: payload))
    }

    static func remove(ids: [Int]) async throws {
        try await APIClient.shared.sendVoid(try Endpoint.delete(path, body: ids, query: [:]))
    }

    static func setEnabled(ids: [Int], enabled: Bool) async throws {
        let endpoint = try Endpoint.put("\(path)/\(enabled ? "enable" : "disable")", body: ids)
        try await APIClient.shared.sendVoid(endpoint)
    }

    static func rename(ids: [Int], name: String) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put("\(path)/name", body: EnvRenamePayload(ids: ids, name: name))
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

    static func pin(ids: [Int], pinned: Bool) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put("\(path)/\(pinned ? "pin" : "unpin")", body: ids)
        )
    }

    static func move(id: Int, fromIndex: Int, toIndex: Int) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put(
                "\(path)/\(id)/move",
                body: MovePayload(fromIndex: fromIndex, toIndex: toIndex)
            )
        )
    }

    /// 通过 JSON 数组批量导入（面板 `/api/envs` POST 直接接收该格式，无需 multipart）
    @discardableResult
    static func importJSON(_ data: Data) async throws -> Int {
        guard let array = try? JSONCoder.decode([EnvCreatePayload].self, from: data) else {
            throw APIError.decoding("导入内容不是合法的环境变量数组，需为 [{\"name\":\"...\",\"value\":\"...\"}]")
        }
        let created = try await create(array)
        return created.count
    }

    /// 导出为面板同款 JSON
    static func exportJSON(_ envs: [QLEnv]) throws -> Data {
        let payloads = envs.map {
            EnvCreatePayload(
                name: $0.name,
                value: $0.value,
                remarks: $0.remarks ?? "",
                labels: $0.labelList
            )
        }
        return try JSONCoder.encode(payloads)
    }
}
