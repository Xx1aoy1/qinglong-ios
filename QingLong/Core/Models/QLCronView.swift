//
//  QLCronView.swift
//  QingLong
//
//  定时任务「视图」。对应后端 `back/data/cronView.ts`：
//  `{ id, name, position, isDisabled, type, filters, sorts, filterRelation }`
//
//  视图是面板侧的别名分组 + 筛选规则，客户端拉取后按同一套语义在本地求值，
//  这样切换视图不会重新请求整个任务列表，也不会破坏列表缓存。
//

import Foundation

// MARK: - 条件字段 / 操作符

/// 视图支持的筛选字段（与面板 `viewCreateModal.tsx` 的 PROPERTIES 一致）
enum CronViewProperty: String, CaseIterable, Identifiable {
    case command
    case name
    case schedule
    case status
    case labels
    case subID = "sub_id"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .command: return "命令"
        case .name: return "名称"
        case .schedule: return "定时规则"
        case .status: return "状态"
        case .labels: return "标签"
        case .subID: return "订阅"
        }
    }

    /// 状态 / 订阅只能「属于 / 不属于」
    var isSelectOnly: Bool { self == .status || self == .subID }

    static func title(for property: String) -> String {
        CronViewProperty(rawValue: property)?.title ?? property
    }
}

/// 视图支持的操作符（与面板 OPERATIONS 一致）
enum CronViewOperation: String, CaseIterable, Identifiable {
    case contains = "Reg"
    case notContains = "NotReg"
    case inside = "In"
    case notInside = "Nin"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contains: return "包含"
        case .notContains: return "不包含"
        case .inside: return "属于"
        case .notInside: return "不属于"
        }
    }

    var isSelect: Bool { self == .inside || self == .notInside }

    static func title(for operation: String) -> String {
        CronViewOperation(rawValue: operation)?.title ?? operation
    }
}

/// 排序字段（面板 sorts 里的 `value`）
enum CronViewSortField: String, CaseIterable, Identifiable {
    case name
    case command
    case schedule
    case status
    case subID = "sub_id"
    case lastRunning = "last_running_time"
    case lastExecution = "last_execution_time"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "名称"
        case .command: return "命令"
        case .schedule: return "定时规则"
        case .status: return "状态"
        case .subID: return "订阅"
        case .lastRunning: return "上次运行时间"
        case .lastExecution: return "上次结束时间"
        }
    }
}

// MARK: - 单条筛选条件

/// `{ property, operation, value }`，`value` 可能是字符串也可能是数组。
struct CronViewFilter: Codable, Hashable {
    var property: String
    var operation: String
    var value: JSONValue?

    init(property: String, operation: String, value: JSONValue?) {
        self.property = property
        self.operation = operation
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        property = (try? container.decodeIfPresent(String.self, forKey: .property)) ?? "command"
        operation = (try? container.decodeIfPresent(String.self, forKey: .operation)) ?? "Reg"
        value = (try? container.decodeIfPresent(JSONValue.self, forKey: .value)) ?? nil
    }

    /// `In` / `Nin` 的候选值
    var valueList: [String] {
        guard let value else { return [] }
        if case .array(let items) = value {
            return items.map(\.stringValue)
        }
        let text = value.stringValue
        return text.isEmpty ? [] : [text]
    }

    /// `Reg` / `NotReg` 的匹配文本
    var text: String {
        guard let value else { return "" }
        switch value {
        case .string(let text):
            return text
        case .number(let number):
            return number == number.rounded() ? String(Int(number)) : String(number)
        case .array:
            return valueList.joined(separator: ",")
        case .bool(let flag):
            return flag ? "true" : "false"
        case .object, .null:
            return ""
        }
    }

    /// 人类可读摘要，用于视图管理列表
    var summary: String {
        let propertyTitle = CronViewProperty.title(for: property)
        let operationTitle = CronViewOperation.title(for: operation)
        let valueText: String
        if CronViewOperation(rawValue: operation)?.isSelect == true {
            let names = valueList
            valueText = names.isEmpty ? "（未选择）" : names.joined(separator: "、")
        } else {
            valueText = text.isEmpty ? "（空）" : text
        }
        return "\(propertyTitle)\(operationTitle)\(valueText)"
    }

    /// 是否是一条实际生效的条件（空条件交给客户端时会匹配全部，没有意义）
    var isUsable: Bool {
        if CronViewOperation(rawValue: operation)?.isSelect == true {
            return !valueList.isEmpty
        }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 比较时统一归一化：数字按整数、文本忽略大小写
    static func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Int(trimmed) { return String(number) }
        return trimmed.lowercased()
    }
}

// MARK: - 排序

/// `{ type: 'ASC' | 'DESC', value: <字段> }`
struct CronViewSort: Codable, Hashable {
    var type: String
    var value: String

    init(type: String, value: String) {
        self.type = type
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "ASC"
        value = (try? container.decodeIfPresent(String.self, forKey: .value)) ?? "name"
    }

    var isAscending: Bool { type.uppercased() != "DESC" }
}

// MARK: - 视图

struct QLCronView: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var position: Double?
    var isDisabled: Int?
    var type: Int?
    var filterRelation: String?
    var filters: [CronViewFilter]
    var sorts: [CronViewSort]

    init(
        id: Int,
        name: String,
        position: Double? = nil,
        isDisabled: Int? = nil,
        type: Int? = nil,
        filterRelation: String? = nil,
        filters: [CronViewFilter] = [],
        sorts: [CronViewSort] = []
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.isDisabled = isDisabled
        self.type = type
        self.filterRelation = filterRelation
        self.filters = filters
        self.sorts = sorts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "未命名视图"
        position = (try? container.decodeIfPresent(Double.self, forKey: .position)) ?? nil
        isDisabled = (try? container.decodeIfPresent(Int.self, forKey: .isDisabled)) ?? nil
        type = (try? container.decodeIfPresent(Int.self, forKey: .type)) ?? nil
        filterRelation = (try? container.decodeIfPresent(String.self, forKey: .filterRelation)) ?? nil
        filters = (try? container.decodeIfPresent([CronViewFilter].self, forKey: .filters)) ?? []
        sorts = (try? container.decodeIfPresent([CronViewSort].self, forKey: .sorts)) ?? []
    }

    /// 面板内置视图（`type == 1`，例如「全部任务」）不允许改名 / 删除
    var isSystem: Bool { type == 1 }
    var isEnabled: Bool { (isDisabled ?? 0) == 0 }
    var isOr: Bool { (filterRelation ?? "and").lowercased() == "or" }
    var hasSorts: Bool { !sorts.isEmpty }

    var conditionSummary: String {
        guard !filters.isEmpty else { return "全部任务" }
        let joiner = isOr ? " 或 " : " 且 "
        return filters.map(\.summary).joined(separator: joiner)
    }

    var sortSummary: String {
        guard let first = sorts.first else { return "" }
        let fieldTitle = CronViewSortField(rawValue: first.value)?.title ?? first.value
        return "\(fieldTitle)\(first.isAscending ? "升序" : "降序")"
    }
}

// MARK: - 客户端求值

extension QLCron {

    /// 按单条条件求值。语义对齐后端 `CronService.formatViewQuery`：
    /// `Reg` = `LIKE %value%`（包含），`NotReg` = 不包含，
    /// `In` / `Nin` = 属于 / 不属于给定集合。
    func matches(_ filter: CronViewFilter) -> Bool {
        let candidates: [String]
        switch filter.property {
        case "command":
            candidates = [command]
        case "name":
            candidates = [title, name ?? ""]
        case "schedule":
            candidates = [schedule ?? ""]
        case "status":
            // `statusValue` 已经把 isDisabled 折算成 2，与面板一致
            candidates = [String(statusValue.rawValue)]
        case "labels":
            candidates = [labelList.joined(separator: ",")]
        case "sub_id":
            candidates = [String(sub_id ?? 0)]
        default:
            return true
        }

        switch filter.operation {
        case "Reg":
            let needle = filter.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !needle.isEmpty else { return true }
            return candidates.contains { $0.lowercased().contains(needle) }
        case "NotReg":
            let needle = filter.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !needle.isEmpty else { return true }
            return !candidates.contains { $0.lowercased().contains(needle) }
        case "In":
            let values = Set(filter.valueList.map(CronViewFilter.normalize))
            guard !values.isEmpty else { return true }
            return candidates.contains { values.contains(CronViewFilter.normalize($0)) }
        case "Nin":
            let values = Set(filter.valueList.map(CronViewFilter.normalize))
            guard !values.isEmpty else { return true }
            return !candidates.contains { values.contains(CronViewFilter.normalize($0)) }
        default:
            return true
        }
    }

    static func compare(_ lhs: QLCron, _ rhs: QLCron, by sort: CronViewSort) -> ComparisonResult {
        switch sort.value {
        case "name":
            return lhs.title.localizedStandardCompare(rhs.title)
        case "command":
            return lhs.command.localizedStandardCompare(rhs.command)
        case "schedule":
            return (lhs.schedule ?? "").localizedStandardCompare(rhs.schedule ?? "")
        case "status":
            let left = lhs.statusValue.rawValue
            let right = rhs.statusValue.rawValue
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        case "sub_id":
            let left = lhs.sub_id ?? 0
            let right = rhs.sub_id ?? 0
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        case "last_running_time":
            let left = lhs.last_running_time ?? 0
            let right = rhs.last_running_time ?? 0
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        case "last_execution_time":
            let left = lhs.last_execution_time ?? 0
            let right = rhs.last_execution_time ?? 0
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        default:
            return .orderedSame
        }
    }
}

extension Array where Element == QLCron {

    /// 按视图的筛选条件与排序规则求值
    func applying(_ view: QLCronView) -> [QLCron] {
        var result = self

        if !view.filters.isEmpty {
            if view.isOr {
                result = result.filter { cron in
                    view.filters.contains { cron.matches($0) }
                }
            } else {
                result = result.filter { cron in
                    view.filters.allSatisfy { cron.matches($0) }
                }
            }
        }

        if !view.sorts.isEmpty {
            result.sort { lhs, rhs in
                for sort in view.sorts {
                    let order = QLCron.compare(lhs, rhs, by: sort)
                    if order != .orderedSame {
                        return sort.isAscending ? order == .orderedAscending : order == .orderedDescending
                    }
                }
                return lhs.id < rhs.id
            }
        }

        return result
    }
}
