//
//  QLOpenApp.swift
//  QingLong
//
//  面板「开放接口」应用（client_id / client_secret），可用于无密码接入。
//

import Foundation

enum AppScope: String, CaseIterable {
    case dashboard
    case envs
    case crons
    case configs
    case scripts
    case logs
    case system

    var title: String {
        switch self {
        case .dashboard: return "仪表盘"
        case .envs: return "环境变量"
        case .crons: return "定时任务"
        case .configs: return "配置"
        case .scripts: return "脚本"
        case .logs: return "日志"
        case .system: return "系统"
        }
    }
}

struct OpenAppToken: Codable, Hashable {
    var value: String?
    var type: String?
    var expiration: Int?
}

struct QLOpenApp: Codable, Identifiable, Hashable {
    var id: Int
    var name: String?
    var scopes: [String]?
    var client_id: String?
    var client_secret: String?
    var tokens: [OpenAppToken]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        scopes = try? container.decodeIfPresent([String].self, forKey: .scopes)
        client_id = try? container.decodeIfPresent(String.self, forKey: .client_id)
        client_secret = try? container.decodeIfPresent(String.self, forKey: .client_secret)
        tokens = try? container.decodeIfPresent([OpenAppToken].self, forKey: .tokens)
    }

    var scopeList: [AppScope] { (scopes ?? []).compactMap(AppScope.init(rawValue:)) }
    var title: String { (name?.isEmpty == false ? name! : "未命名应用") }
    var activeTokenCount: Int {
        let now = Int(Date().timeIntervalSince1970)
        return (tokens ?? []).filter { ($0.expiration ?? 0) > now }.count
    }
}

struct OpenAppPayload: Encodable {
    var id: Int?
    var name: String
    var scopes: [String]
}
