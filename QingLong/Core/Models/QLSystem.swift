//
//  QLSystem.swift
//  QingLong
//

import Foundation

/// `GET /api/system/config`
struct SystemConfig: Codable, Equatable {
    var id: Int?
    var type: String?
    var info: SystemConfigInfo?

    var infoOrEmpty: SystemConfigInfo { info ?? SystemConfigInfo() }
}

struct SystemConfigInfo: Codable, Equatable {
    var logRemoveFrequency: Int?
    var cronConcurrency: Int?
    var dependenceProxy: String?
    var nodeMirror: String?
    var pythonMirror: String?
    var linuxMirror: String?
    var timezone: String?
    var lang: String?
    var panelTitle: String?
    var globalSshKey: String?

    init(
        logRemoveFrequency: Int? = nil,
        cronConcurrency: Int? = nil,
        dependenceProxy: String? = nil,
        nodeMirror: String? = nil,
        pythonMirror: String? = nil,
        linuxMirror: String? = nil,
        timezone: String? = nil,
        lang: String? = nil,
        panelTitle: String? = nil,
        globalSshKey: String? = nil
    ) {
        self.logRemoveFrequency = logRemoveFrequency
        self.cronConcurrency = cronConcurrency
        self.dependenceProxy = dependenceProxy
        self.nodeMirror = nodeMirror
        self.pythonMirror = pythonMirror
        self.linuxMirror = linuxMirror
        self.timezone = timezone
        self.lang = lang
        self.panelTitle = panelTitle
        self.globalSshKey = globalSshKey
    }

    /// 已知时区（面板后端使用 moment-timezone，这里只提供常用项）
    static let commonTimezones = [
        "Asia/Shanghai",
        "Asia/Hong_Kong",
        "Asia/Taipei",
        "Asia/Tokyo",
        "Asia/Singapore",
        "UTC",
        "Europe/London",
        "America/New_York",
        "America/Los_Angeles"
    ]

    static let commonLanguages = ["zh_CN", "zh_TW", "en_US"]
}

/// 面板更新检查结果 `/api/system/update-check`
struct UpdateCheckResult: Codable, Equatable {
    var version: String?
    var lastVersion: String?
    var lastPublishTime: Int?
    var lastVersionLink: String?
}

/// 命令调试返回的分片
struct CommandRunResult: Codable, Equatable {
    var code: Int?
    var message: String?
}
