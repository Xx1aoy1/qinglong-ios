//
//  DateFormatting.swift
//  QingLong
//

import Foundation

extension Date {
    /// 相对时间描述：刚刚 / 3 分钟前 / 2 天前
    var relativeDescription: String {
        let interval = Date().timeIntervalSince(self)
        if interval < 0 {
            return Self.absoluteFormatter.string(from: self)
        }
        switch interval {
        case ..<60:
            return "刚刚"
        case ..<3600:
            return "\(Int(interval / 60)) 分钟前"
        case ..<86400:
            return "\(Int(interval / 3600)) 小时前"
        case ..<86400 * 7:
            return "\(Int(interval / 86400)) 天前"
        default:
            return Self.shortFormatter.string(from: self)
        }
    }

    var absoluteDescription: String { Self.absoluteFormatter.string(from: self) }

    static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

extension Int {
    /// 时间戳（秒）→ 相对时间
    var timestampRelativeDescription: String {
        guard self > 0 else { return "—" }
        return Date(timeIntervalSince1970: TimeInterval(self)).relativeDescription
    }

    /// 秒数 → 「1 分 20 秒」
    var durationDescription: String {
        guard self > 0 else { return "0 秒" }
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) 小时") }
        if minutes > 0 { parts.append("\(minutes) 分") }
        if seconds > 0 || parts.isEmpty { parts.append("\(seconds) 秒") }
        return parts.joined(separator: " ")
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 把多行文本按行拆分并去空行
    var nonEmptyLines: [String] {
        components(separatedBy: .newlines)
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
    }
}
