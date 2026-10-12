//
//  QLStatus.swift
//  QingLong
//
//  面板各类状态枚举（与后端 `back/data/*.ts` 中的枚举数值严格对应）。
//

import SwiftUI

/// UI 语义色调，由 Theme 映射为具体颜色，保证深浅色模式一致。
enum StatusTone {
    case neutral
    case success
    case warning
    case danger
    case info
    case progress

    var color: Color {
        switch self {
        case .neutral: return Theme.textSecondary
        case .success: return Theme.success
        case .warning: return Theme.warning
        case .danger: return Theme.danger
        case .info: return Theme.info
        case .progress: return Theme.brand
        }
    }
}

// MARK: - 定时任务状态

enum CronStatus: Int {
    case running = 0
    case idle = 1
    case disabled = 2
    case queued = 3

    var title: String {
        switch self {
        case .running: return "运行中"
        case .idle: return "空闲"
        case .disabled: return "已禁用"
        case .queued: return "排队中"
        }
    }

    var tone: StatusTone {
        switch self {
        case .running: return .progress
        case .idle: return .success
        case .disabled: return .neutral
        case .queued: return .warning
        }
    }

    var symbol: String {
        switch self {
        case .running: return "play.circle.fill"
        case .idle: return "checkmark.circle.fill"
        case .disabled: return "pause.circle.fill"
        case .queued: return "clock.fill"
        }
    }
}

// MARK: - 环境变量状态

enum EnvStatus: Int {
    case normal = 0
    case disabled = 1

    var title: String { self == .normal ? "已启用" : "已禁用" }
    var tone: StatusTone { self == .normal ? .success : .neutral }
}

// MARK: - 订阅状态

enum SubscriptionStatus: Int {
    case running = 0
    case idle = 1
    case disabled = 2
    case queued = 3

    var title: String {
        switch self {
        case .running: return "拉取中"
        case .idle: return "空闲"
        case .disabled: return "已禁用"
        case .queued: return "排队中"
        }
    }

    var tone: StatusTone {
        switch self {
        case .running: return .progress
        case .idle: return .success
        case .disabled: return .neutral
        case .queued: return .warning
        }
    }
}

// MARK: - 依赖状态

enum DependenceStatus: Int {
    case installing = 0
    case installed = 1
    case installFailed = 2
    case removing = 3
    case removed = 4
    case removeFailed = 5
    case queued = 6
    case cancelled = 7

    var title: String {
        switch self {
        case .installing: return "安装中"
        case .installed: return "已安装"
        case .installFailed: return "安装失败"
        case .removing: return "卸载中"
        case .removed: return "已卸载"
        case .removeFailed: return "卸载失败"
        case .queued: return "排队中"
        case .cancelled: return "已取消"
        }
    }

    var tone: StatusTone {
        switch self {
        case .installing, .removing, .queued: return .progress
        case .installed: return .success
        case .installFailed, .removeFailed: return .danger
        case .removed, .cancelled: return .neutral
        }
    }

    /// 是否处于进行中（需要轮询刷新）
    var isBusy: Bool {
        self == .installing || self == .removing || self == .queued
    }
}

enum DependenceType: Int, CaseIterable {
    case nodejs = 0
    case python3 = 1
    case linux = 2

    var title: String {
        switch self {
        case .nodejs: return "Node.js"
        case .python3: return "Python3"
        case .linux: return "Linux"
        }
    }

    var shortTitle: String {
        switch self {
        case .nodejs: return "Node"
        case .python3: return "Python"
        case .linux: return "Linux"
        }
    }

    var symbol: String {
        switch self {
        case .nodejs: return "hexagon.fill"
        case .python3: return "chevron.left.forwardslash.chevron.right"
        case .linux: return "terminal.fill"
        }
    }

    var tone: StatusTone {
        switch self {
        case .nodejs: return .success
        case .python3: return .info
        case .linux: return .warning
        }
    }
}

// MARK: - 订阅类型

enum SubscriptionType: String, CaseIterable {
    case publicRepo = "public-repo"
    case privateRepo = "private-repo"
    case file = "file"

    var title: String {
        switch self {
        case .publicRepo: return "公开仓库"
        case .privateRepo: return "私有仓库"
        case .file: return "单文件"
        }
    }
}

enum SubscriptionScheduleType: String, CaseIterable {
    case crontab
    case interval

    var title: String { self == .crontab ? "cron 表达式" : "固定间隔" }
}

enum IntervalUnit: String, CaseIterable {
    case seconds
    case minutes
    case hours
    case days

    var title: String {
        switch self {
        case .seconds: return "秒"
        case .minutes: return "分钟"
        case .hours: return "小时"
        case .days: return "天"
        }
    }

    var multiplier: Int {
        switch self {
        case .seconds: return 1
        case .minutes: return 60
        case .hours: return 3600
        case .days: return 86400
        }
    }
}
