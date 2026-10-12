//
//  QLCron.swift
//  QingLong
//
//  定时任务。对应后端 `back/data/cron.ts` 与 `back/validation/schedule.ts`。
//

import Foundation

struct CronExtraSchedule: Codable, Hashable {
    var schedule: String
}

struct QLCron: Codable, Identifiable, Hashable {
    var id: Int
    var name: String?
    var command: String
    var schedule: String?
    var status: Int?
    var isDisabled: Int?
    var isPinned: Int?
    var isSystem: Int?
    var pid: Int?
    var log_path: String?
    var labels: [String]?
    var last_running_time: Int?
    var last_execution_time: Int?
    var sub_id: Int?
    var task_before: String?
    var task_after: String?
    var log_name: String?
    var allow_multiple_instances: Int?
    var work_dir: String?
    var extra_schedules: [CronExtraSchedule]?
    var saved: Bool?

    init(
        id: Int,
        name: String? = nil,
        command: String,
        schedule: String? = nil,
        status: Int? = nil,
        isDisabled: Int? = nil,
        isPinned: Int? = nil,
        isSystem: Int? = nil,
        pid: Int? = nil,
        log_path: String? = nil,
        labels: [String]? = nil,
        last_running_time: Int? = nil,
        last_execution_time: Int? = nil,
        sub_id: Int? = nil,
        task_before: String? = nil,
        task_after: String? = nil,
        log_name: String? = nil,
        allow_multiple_instances: Int? = nil,
        work_dir: String? = nil,
        extra_schedules: [CronExtraSchedule]? = nil,
        saved: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.schedule = schedule
        self.status = status
        self.isDisabled = isDisabled
        self.isPinned = isPinned
        self.isSystem = isSystem
        self.pid = pid
        self.log_path = log_path
        self.labels = labels
        self.last_running_time = last_running_time
        self.last_execution_time = last_execution_time
        self.sub_id = sub_id
        self.task_before = task_before
        self.task_after = task_after
        self.log_name = log_name
        self.allow_multiple_instances = allow_multiple_instances
        self.work_dir = work_dir
        self.extra_schedules = extra_schedules
        self.saved = saved
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        command = (try? container.decode(String.self, forKey: .command)) ?? ""
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        schedule = try? container.decodeIfPresent(String.self, forKey: .schedule)
        status = try? container.decodeIfPresent(Int.self, forKey: .status)
        isDisabled = try? container.decodeIfPresent(Int.self, forKey: .isDisabled)
        isPinned = try? container.decodeIfPresent(Int.self, forKey: .isPinned)
        isSystem = try? container.decodeIfPresent(Int.self, forKey: .isSystem)
        pid = try? container.decodeIfPresent(Int.self, forKey: .pid)
        log_path = try? container.decodeIfPresent(String.self, forKey: .log_path)
        labels = try? container.decodeIfPresent([String].self, forKey: .labels)
        last_running_time = try? container.decodeIfPresent(Int.self, forKey: .last_running_time)
        last_execution_time = try? container.decodeIfPresent(Int.self, forKey: .last_execution_time)
        sub_id = try? container.decodeIfPresent(Int.self, forKey: .sub_id)
        task_before = try? container.decodeIfPresent(String.self, forKey: .task_before)
        task_after = try? container.decodeIfPresent(String.self, forKey: .task_after)
        log_name = try? container.decodeIfPresent(String.self, forKey: .log_name)
        allow_multiple_instances = try? container.decodeIfPresent(Int.self, forKey: .allow_multiple_instances)
        work_dir = try? container.decodeIfPresent(String.self, forKey: .work_dir)
        extra_schedules = try? container.decodeIfPresent([CronExtraSchedule].self, forKey: .extra_schedules)
        saved = try? container.decodeIfPresent(Bool.self, forKey: .saved)
    }

    var title: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? command : trimmed
    }

    var statusValue: CronStatus {
        if isDisabled == 1 { return .disabled }
        return CronStatus(rawValue: status ?? CronStatus.idle.rawValue) ?? .idle
    }

    var isPinnedValue: Bool { isPinned == 1 }
    var isSystemTask: Bool { isSystem == 1 }
    var labelList: [String] { labels ?? [] }
    var isFromSubscription: Bool { (sub_id ?? 0) > 0 }

    var lastRunText: String {
        guard let last = last_running_time, last > 0 else { return "从未运行" }
        return Date(timeIntervalSince1970: TimeInterval(last)).relativeDescription
    }

    var lastFinishedText: String {
        guard let last = last_execution_time, last > 0 else { return "—" }
        return Date(timeIntervalSince1970: TimeInterval(last)).relativeDescription
    }

    /// 是否为「跑一次」类型的任务（面板约定 `@once`）
    var isOneShot: Bool {
        let value = schedule ?? ""
        return value.hasPrefix("@once") || value.hasPrefix("once")
    }

    /// 是否为「容器启动时运行」（面板约定 `@boot`）
    var isBootTask: Bool {
        (schedule ?? "").hasPrefix("@boot")
    }
}

/// 新建 / 更新定时任务的请求体
struct CronPayload: Encodable {
    var id: Int?
    var name: String
    var command: String
    var schedule: String
    var labels: [String]
    var task_before: String?
    var task_after: String?
    var log_name: String?
    var allow_multiple_instances: Int?
    var work_dir: String?
    var extra_schedules: [CronExtraSchedule]?

    init(
        id: Int? = nil,
        name: String,
        command: String,
        schedule: String,
        labels: [String] = [],
        task_before: String? = nil,
        task_after: String? = nil,
        log_name: String? = nil,
        allow_multiple_instances: Int? = nil,
        work_dir: String? = nil,
        extra_schedules: [CronExtraSchedule]? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.schedule = schedule
        self.labels = labels
        self.task_before = task_before
        self.task_after = task_after
        self.log_name = log_name
        self.allow_multiple_instances = allow_multiple_instances
        self.work_dir = work_dir
        self.extra_schedules = extra_schedules
    }
}

extension Array where Element == QLCron {
    var allLabels: [String] {
        Array(Set(flatMap { $0.labelList })).sorted()
    }

    func search(_ keyword: String) -> [QLCron] {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return self }
        return filter { cron in
            cron.title.lowercased().contains(text)
                || cron.command.lowercased().contains(text)
                || (cron.schedule ?? "").lowercased().contains(text)
                || cron.labelList.contains { $0.lowercased().contains(text) }
        }
    }

    var runningCount: Int { filter { $0.statusValue == .running }.count }
    var enabledCount: Int { filter { $0.statusValue != .disabled }.count }
}
