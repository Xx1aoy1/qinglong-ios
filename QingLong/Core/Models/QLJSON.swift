//
//  QLJSON.swift
//  QingLong
//
//  任意 JSON 值。用于结构不固定的字段（通知渠道配置、订阅 pull_option 等），
//  避免为几十种通知渠道各写一套 Codable。
//

import Foundation

enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    // MARK: - 取值便利

    var stringValue: String {
        switch self {
        case .string(let value): return value
        case .number(let value):
            return value == value.rounded() ? String(Int(value)) : String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return ""
        case .array, .object:
            if let data = try? JSONCoder.encode(self),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
            return ""
        }
    }

    var boolValue: Bool {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        case .string(let value): return value == "true" || value == "1"
        default: return false
        }
    }

    var intValue: Int? {
        switch self {
        case .number(let value): return Int(value)
        case .string(let value): return Int(value)
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }

    static func from(_ any: Any) -> JSONValue {
        switch any {
        case let value as String: return .string(value)
        case let value as Bool: return .bool(value)
        case let value as Int: return .number(Double(value))
        case let value as Double: return .number(value)
        case let value as [String: Any]: return .object(value.mapValues(JSONValue.from))
        case let value as [Any]: return .array(value.map(JSONValue.from))
        default: return .null
        }
    }
}

/// `[String: JSONValue]` 的读写糖
extension Dictionary where Key == String, Value == JSONValue {
    func string(_ key: String, default def: String = "") -> String {
        guard let value = self[key] else { return def }
        return value.stringValue
    }

    func bool(_ key: String, default def: Bool = false) -> Bool {
        guard let value = self[key] else { return def }
        return value.boolValue
    }

    func int(_ key: String) -> Int? {
        self[key]?.intValue
    }

    mutating func setString(_ key: String, _ value: String) {
        self[key] = value.isEmpty ? nil : .string(value)
    }

    mutating func setBool(_ key: String, _ value: Bool) {
        self[key] = .bool(value)
    }
}
