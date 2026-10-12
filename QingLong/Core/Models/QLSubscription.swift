//
//  QLSubscription.swift
//  QingLong
//

import Foundation

struct IntervalSchedule: Codable, Hashable {
    var type: String
    var value: Int

    var unit: IntervalUnit { IntervalUnit(rawValue: type) ?? .hours }

    var description: String { "每 \(value) \(unit.title)" }
}

struct QLSubscription: Codable, Identifiable, Hashable {
    var id: Int
    var name: String?
    var alias: String
    var type: String?
    var schedule_type: String?
    var schedule: String?
    var interval_schedule: IntervalSchedule?
    var url: String
    var whitelist: String?
    var blacklist: String?
    var dependences: String?
    var branch: String?
    var status: Int?
    var pull_type: String?
    var is_disabled: Int?
    var log_path: String?
    var pid: Int?
    var extensions: String?
    var sub_before: String?
    var sub_after: String?
    var proxy: String?
    var autoAddCron: Int?
    var autoDelCron: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        url = (try? container.decode(String.self, forKey: .url)) ?? ""
        alias = (try? container.decode(String.self, forKey: .alias)) ?? ""
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        schedule_type = try? container.decodeIfPresent(String.self, forKey: .schedule_type)
        schedule = try? container.decodeIfPresent(String.self, forKey: .schedule)
        interval_schedule = try? container.decodeIfPresent(IntervalSchedule.self, forKey: .interval_schedule)
        whitelist = try? container.decodeIfPresent(String.self, forKey: .whitelist)
        blacklist = try? container.decodeIfPresent(String.self, forKey: .blacklist)
        dependences = try? container.decodeIfPresent(String.self, forKey: .dependences)
        branch = try? container.decodeIfPresent(String.self, forKey: .branch)
        status = try? container.decodeIfPresent(Int.self, forKey: .status)
        pull_type = try? container.decodeIfPresent(String.self, forKey: .pull_type)
        is_disabled = try? container.decodeIfPresent(Int.self, forKey: .is_disabled)
        log_path = try? container.decodeIfPresent(String.self, forKey: .log_path)
        pid = try? container.decodeIfPresent(Int.self, forKey: .pid)
        extensions = try? container.decodeIfPresent(String.self, forKey: .extensions)
        sub_before = try? container.decodeIfPresent(String.self, forKey: .sub_before)
        sub_after = try? container.decodeIfPresent(String.self, forKey: .sub_after)
        proxy = try? container.decodeIfPresent(String.self, forKey: .proxy)
        autoAddCron = try? container.decodeIfPresent(Int.self, forKey: .autoAddCron)
        autoDelCron = try? container.decodeIfPresent(Int.self, forKey: .autoDelCron)
    }

    var title: String {
        let nameText = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !nameText.isEmpty { return nameText }
        let aliasText = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return aliasText.isEmpty ? url : aliasText
    }

    var statusValue: SubscriptionStatus {
        if is_disabled == 1 { return .disabled }
        return SubscriptionStatus(rawValue: status ?? SubscriptionStatus.idle.rawValue) ?? .idle
    }

    var typeValue: SubscriptionType { SubscriptionType(rawValue: type ?? "") ?? .publicRepo }
    var scheduleTypeValue: SubscriptionScheduleType {
        SubscriptionScheduleType(rawValue: schedule_type ?? "") ?? .crontab
    }
    var isAutoAddCron: Bool { autoAddCron == 1 }
    var isAutoDelCron: Bool { autoDelCron == 1 }

    var scheduleDescription: String {
        if scheduleTypeValue == .interval, let interval = interval_schedule {
            return interval.description
        }
        return schedule ?? "—"
    }
}

/// 新建 / 更新订阅的请求体
struct SubscriptionPayload: Encodable {
    var id: Int?
    var type: String
    var schedule_type: String
    var schedule: String?
    var interval_schedule: IntervalSchedule?
    var name: String
    var alias: String
    var url: String
    var whitelist: String?
    var blacklist: String?
    var branch: String?
    var dependences: String?
    var extensions: String?
    var sub_before: String?
    var sub_after: String?
    var proxy: String?
    var autoAddCron: Bool
    var autoDelCron: Bool
    var pull_type: String?
    var pull_option: JSONValue?
}

extension Array where Element == QLSubscription {
    var allAliases: [String] { map(\.alias).filter { !$0.isEmpty } }

    func search(_ keyword: String) -> [QLSubscription] {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return self }
        return filter { item in
            item.title.lowercased().contains(text)
                || item.alias.lowercased().contains(text)
                || item.url.lowercased().contains(text)
        }
    }
}
