//
//  QLUser.swift
//  QingLong
//

import Foundation

/// `GET /api/user`
struct QLUser: Codable, Equatable {
    var username: String?
    var avatar: String?
    var twoFactorActivated: Bool?

    static let placeholder = QLUser(username: "admin", avatar: nil, twoFactorActivated: false)
}

/// `/api/system`（白名单接口，无需登录）
struct SystemStatus: Codable, Equatable {
    var isInitialized: Bool?
    var version: String?
    var publishTime: Int?
    var branch: String?
    var changeLog: String?
    var changeLogLink: String?

    var publishDateText: String {
        guard let publishTime else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(publishTime)))
    }
}

/// `POST /api/user/login` 成功时的 data
struct LoginResult: Codable, Equatable {
    var token: String?
    var lastip: String?
    var lastaddr: String?
    var lastlogon: Int?
    var retries: Int?
    var platform: String?
}

/// `GET /api/user/login-log`
/// 青龙 2.22+ 直接返回扁平的 info 对象数组（无 id/type/info 包裹），
/// 更早版本返回 `{ id, type, info }`，两种形态都兼容。
struct LoginLogItem: Codable, Identifiable, Equatable {
    var id: Int?
    var type: String?
    var info: Info?

    struct Info: Codable, Equatable {
        var timestamp: Int?
        var address: String?
        var ip: String?
        var platform: String?
        var status: Int?
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, info, timestamp, address, ip, platform, status
    }

    init(id: Int? = nil, type: String? = nil, info: Info?) {
        self.id = id
        self.type = type
        self.info = info
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(Int.self, forKey: .id)
        type = try? container.decodeIfPresent(Vfjxct.self, forKey: .type)
        if let nested = try? container.decodeIfPresent(Info.self, forKey: .info) {
            info = nested
            return
        }
        // 扁平结构
        info = Info(
            timestamp: try? container.decodeIfPresent(Int.self, forKey: .timestamp),
            address: try? container.decodeIfPresent(Vfjxct.self, forKey: .address),
            ip: try? container.decodeIfPresent(Vfjxct.self, forKey: .ip),
            platform: try? container.decodeIfPresent(Vfjxct.self, forKey: .platform),
            status: try? container.decodeIfPresent(Int.self, forKey: .status)
        )
    }

    var isSuccess: Bool { info?.status == 0 }
}

/// `/api/user/two-factor/init`
struct TwoFactorSetup: Codable, Equatable {
    var secret: String?
    var url: String?
}
