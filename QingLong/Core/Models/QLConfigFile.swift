//
//  QLConfigFile.swift
//  QingLong
//
//  面板 `config/` 目录下的配置文件。对应 `GET /api/configs/files` 的
//  `{ title, value }`（两者通常都是文件名）。
//

import Foundation

struct QLConfigFile: Codable, Identifiable, Hashable {
    var title: String
    var value: String

    init(title: String, value: String) {
        self.title = title
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawTitle = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
        let rawValue = (try? container.decodeIfPresent(String.self, forKey: .value)) ?? ""
        title = rawTitle.isEmpty ? rawValue : rawTitle
        value = rawValue.isEmpty ? rawTitle : rawValue
    }

    var id: String { value }

    /// 面板侧路径（`/configs/detail` 的 `path` 参数）
    var path: String { value }

    var fileExtension: String {
        (title as NSString).pathExtension.lowercased()
    }

    var symbol: String {
        switch fileExtension {
        case "sh", "bash": return "terminal"
        case "js", "mjs": return "curlybraces"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "json": return "list.bullet.rectangle"
        case "md", "txt": return "doc.text"
        default: return "doc"
        }
    }

    var summary: String {
        Self.summaries[title] ?? "面板配置文件"
    }

    /// 常见配置文件的用途说明（面板版本不同可能没有这些文件，缺失就不显示）
    private static let summaries: [String: String] = [
        "config.sh": "全局配置：通知渠道、HACK、镜像与依赖参数",
        "extra.sh": "容器启动后执行的额外命令",
        "task_before.sh": "所有任务执行前运行的脚本",
        "task_after.sh": "所有任务执行后运行的脚本",
        "repo.sh": "订阅仓库地址（旧版脚本）",
        "sendNotify.js": "通知发送脚本（Node）",
        "sendNotify.py": "通知发送脚本（Python）",
        "notify.js": "通知模板",
        "crontab.list": "整份任务清单（导入导出用）"
    ]
}

extension Array where Element == QLConfigFile {
    /// 常用文件排在前面，其余按名称排序
    var sortedForDisplay: [QLConfigFile] {
        let priority: [String] = [
            "config.sh", "extra.sh", "task_before.sh", "task_after.sh"
        ]
        return sorted { lhs, rhs in
            let left = priority.firstIndex(of: lhs.title) ?? priority.count
            let right = priority.firstIndex(of: rhs.title) ?? priority.count
            if left != right { return left < right }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    func filtered(keyword: String) -> [QLConfigFile] {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return self }
        return filter {
            $0.title.lowercased().contains(text) || $0.summary.lowercased().contains(text)
        }
    }
}
