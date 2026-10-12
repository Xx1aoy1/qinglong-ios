//
//  QLNotification.swift
//  QingLong
//
//  通知设置。面板把这个配置存成一个「扁平的对象」：
//      { "type": "bark", "barkPush": "https://...", "barkGroup": "qinglong", ... }
//  `GET /api/user/notification` 直接返回它，`PUT` 时把同样结构回传，面板会立刻
//  发一条测试通知，成功才落库（失败返回 code 400）。所以「保存」即「测试」。
//

import Foundation

struct NotificationSettings: Codable, Equatable {
    /// 渠道标识，对应后端 NotificationMode
    var type: String
    /// 渠道的其余字段
    var values: [String: JSONValue]

    init(type: String, values: [String: JSONValue] = [:]) {
        self.type = type
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode([String: JSONValue].self)) ?? [:]
        var mutable = raw
        var channel = "gotify"
        if case .string(let value)? = mutable.removeValue(forKey: "type") {
            channel = value
        }
        self.type = channel
        self.values = mutable
    }

    func encode(to encoder: Encoder) throws {
        var object = values
        object["type"] = .string(type)
        var container = encoder.singleValueContainer()
        try container.encode(object)
    }

    func string(_ key: String) -> String { values.string(key) }
    func bool(_ key: String) -> Bool { values.bool(key) }
}

// MARK: - 渠道目录

struct NotificationField: Identifiable {
    enum Kind {
        case text
        case secure
        case number
        case multiline
    }

    var key: String
    var label: String
    var placeholder: String
    var kind: Kind
    var hint: String?

    var id: String { key }

    init(
        _ key: String,
        _ label: String,
        placeholder: String = "",
        kind: Kind = .text,
        hint: String? = nil
    ) {
        self.key = key
        self.label = label
        self.placeholder = placeholder
        self.kind = kind
        self.hint = hint
    }
}

struct NotificationChannel: Identifiable {
    var type: String
    var title: String
    var symbol: String
    var fields: [NotificationField]

    var id: String { type }
}

enum NotificationCatalog {

    static let channels: [NotificationChannel] = [
        NotificationChannel(
            type: "bark",
            title: "Bark",
            symbol: "bell.badge.fill",
            fields: [
                NotificationField("barkPush", "推送地址", placeholder: "https://api.day.app/你的Key"),
                NotificationField("barkGroup", "分组", placeholder: "qinglong"),
                NotificationField("barkSound", "铃声", placeholder: "例如 alarm"),
                NotificationField("barkIcon", "图标地址", placeholder: "https://"),
                NotificationField("barkLevel", "中断级别", placeholder: "active / timeSensitive / critical"),
                NotificationField("barkUrl", "跳转地址", placeholder: "https://"),
                NotificationField("barkArchive", "归档", placeholder: "留空或 1")
            ]
        ),
        NotificationChannel(
            type: "email",
            title: "邮箱",
            symbol: "envelope.fill",
            fields: [
                NotificationField("emailService", "SMTP 服务器", placeholder: "smtp.qq.com"),
                NotificationField("emailUser", "用户名 / 发件邮箱", placeholder: "you@qq.com"),
                NotificationField("emailPass", "密码 / 授权码", kind: .secure),
                NotificationField("emailTo", "收件邮箱", placeholder: "多个用逗号分隔")
            ]
        ),
        NotificationChannel(
            type: "telegramBot",
            title: "Telegram Bot",
            symbol: "paperplane.fill",
            fields: [
                NotificationField("telegramBotToken", "Bot Token", kind: .secure),
                NotificationField("telegramBotUserId", "接收者 UserID / 群 ID"),
                NotificationField("telegramBotApiHost", "API 地址", placeholder: "https://api.telegram.org"),
                NotificationField("telegramBotProxyHost", "代理 Host", placeholder: "可选"),
                NotificationField("telegramBotProxyPort", "代理 Port", placeholder: "可选"),
                NotificationField("telegramBotProxyAuth", "代理认证", placeholder: "user:pass", kind: .secure)
            ]
        ),
        NotificationChannel(
            type: "dingtalkBot",
            title: "钉钉机器人",
            symbol: "bubble.left.and.bubble.right.fill",
            fields: [
                NotificationField("dingtalkBotToken", "AccessToken", kind: .secure),
                NotificationField("dingtalkBotSecret", "加签 Secret", kind: .secure)
            ]
        ),
        NotificationChannel(
            type: "weWorkBot",
            title: "企业微信机器人",
            symbol: "person.3.fill",
            fields: [
                NotificationField("weWorkBotKey", "Webhook Key", kind: .secure),
                NotificationField("weWorkOrigin", "接口地址", placeholder: "https://qyapi.weixin.qq.com")
            ]
        ),
        NotificationChannel(
            type: "weWorkApp",
            title: "企业微信应用",
            symbol: "person.crop.square.fill",
            fields: [
                NotificationField("weWorkAppKey", "应用 Secret / 配置", kind: .secure,
                                  hint: "格式：corpId|corpSecret|agentId"),
                NotificationField("weWorkOrigin", "接口地址", placeholder: "https://qyapi.weixin.qq.com")
            ]
        ),
        NotificationChannel(
            type: "feishu",
            title: "飞书机器人",
            symbol: "paperplane.circle.fill",
            fields: [
                NotificationField("larkKey", "Webhook 地址", placeholder: "https://open.feishu.cn/open-apis/bot/v2/hook/xxx"),
                NotificationField("larkSecret", "签名校验 Secret", kind: .secure)
            ]
        ),
        NotificationChannel(
            type: "serverChan",
            title: "Server 酱",
            symbol: "server.rack",
            fields: [
                NotificationField("serverChanKey", "SendKey", kind: .secure)
            ]
        ),
        NotificationChannel(
            type: "pushDeer",
            title: "PushDeer",
            symbol: "heart.fill",
            fields: [
                NotificationField("pushDeerKey", "PushKey", kind: .secure),
                NotificationField("pushDeerUrl", "自建地址", placeholder: "https://api2.pushdeer.com")
            ]
        ),
        NotificationChannel(
            type: "pushPlus",
            title: "PushPlus",
            symbol: "plus.circle.fill",
            fields: [
                NotificationField("pushPlusToken", "Token", kind: .secure),
                NotificationField("pushPlusUser", "好友令牌"),
                NotificationField("pushPlusTemplate", "模板", placeholder: "html / txt / json"),
                NotificationField("pushplusChannel", "渠道", placeholder: "wechat / webhook / cp"),
                NotificationField("pushplusWebhook", "Webhook 地址"),
                NotificationField("pushplusCallbackUrl", "回调地址"),
                NotificationField("pushplusTo", "目标")
            ]
        ),
        NotificationChannel(
            type: "gotify",
            title: "Gotify",
            symbol: "bolt.fill",
            fields: [
                NotificationField("gotifyUrl", "服务地址", placeholder: "https://push.example.com"),
                NotificationField("gotifyToken", "应用 Token", kind: .secure),
                NotificationField("gotifyPriority", "优先级", placeholder: "0", kind: .number)
            ]
        ),
        NotificationChannel(
            type: "goCqHttpBot",
            title: "GoCQHTTP Bot",
            symbol: "message.fill",
            fields: [
                NotificationField("goCqHttpBotUrl", "接口地址", placeholder: "http://127.0.0.1:5700"),
                NotificationField("goCqHttpBotToken", "Token", kind: .secure),
                NotificationField("goCqHttpBotQq", "接收 QQ / 群号")
            ]
        ),
        NotificationChannel(
            type: "pushMe",
            title: "PushMe",
            symbol: "hand.raised.fill",
            fields: [
                NotificationField("pushMeKey", "PushKey", kind: .secure),
                NotificationField("pushMeUrl", "自建地址")
            ]
        ),
        NotificationChannel(
            type: "aibotk",
            title: "AiBotK",
            symbol: "cpu",
            fields: [
                NotificationField("aibotkKey", "API Key", kind: .secure),
                NotificationField("aibotkType", "类型", placeholder: "room 或 contact"),
                NotificationField("aibotkName", "房间 / 联系人名称")
            ]
        ),
        NotificationChannel(
            type: "iGot",
            title: "iGot",
            symbol: "app.badge.fill",
            fields: [
                NotificationField("iGotPushKey", "Push Key", kind: .secure)
            ]
        ),
        NotificationChannel(
            type: "wePlusBot",
            title: "WePlus Bot",
            symbol: "w.circle.fill",
            fields: [
                NotificationField("wePlusBotToken", "Token", kind: .secure),
                NotificationField("wePlusBotReceiver", "接收者"),
                NotificationField("wePlusBotVersion", "接口版本")
            ]
        ),
        NotificationChannel(
            type: "wxPusherBot",
            title: "WxPusher（应用）",
            symbol: "megaphone.fill",
            fields: [
                NotificationField("wxPusherBotAppToken", "AppToken", kind: .secure),
                NotificationField("wxPusherBotTopicIds", "TopicIds"),
                NotificationField("wxPusherBotUids", "Uids")
            ]
        ),
        NotificationChannel(
            type: "ntfy",
            title: "ntfy",
            symbol: "dot.radiowaves.left.and.right",
            fields: [
                NotificationField("ntfyUrl", "服务地址", placeholder: "https://ntfy.sh"),
                NotificationField("ntfyTopic", "Topic"),
                NotificationField("ntfyPriority", "优先级", placeholder: "default / high / urgent"),
                NotificationField("ntfyToken", "Token", kind: .secure),
                NotificationField("ntfyUsername", "用户名"),
                NotificationField("ntfyPassword", "密码", kind: .secure),
                NotificationField("ntfyActions", "Actions")
            ]
        ),
        NotificationChannel(
            type: "chat",
            title: "Synology Chat",
            symbol: "bubble.left.fill",
            fields: [
                NotificationField("synologyChatUrl", "Webhook 地址", kind: .secure)
            ]
        ),
        NotificationChannel(
            type: "webhook",
            title: "Webhook",
            symbol: "arrow.triangle.branch",
            fields: [
                NotificationField("webhookUrl", "请求地址", placeholder: "https://"),
                NotificationField("webhookMethod", "请求方法", placeholder: "GET / POST / PUT"),
                NotificationField("webhookContentType", "Content-Type", placeholder: "application/json"),
                NotificationField("webhookHeaders", "自定义请求头", kind: .multiline,
                                  hint: "每行一个，形如 Header-Name: value"),
                NotificationField("webhookBody", "请求体", kind: .multiline,
                                  hint: "支持 {{title}} / {{content}} 变量占位")
            ]
        ),
        NotificationChannel(
            type: "chronocat",
            title: "Chronocat",
            symbol: "pawprint.fill",
            fields: [
                NotificationField("chronocatURL", "服务地址", placeholder: "http://127.0.0.1:16530"),
                NotificationField("chronocatQQ", "接收 QQ / 群号"),
                NotificationField("chronocatToken", "Token", kind: .secure)
            ]
        ),
        NotificationChannel(
            type: "openiLink",
            title: "OpeniLink",
            symbol: "link.circle.fill",
            fields: [
                NotificationField("openiLinkAppToken", "AppToken", kind: .secure),
                NotificationField("openiLinkHubUrl", "Hub 地址"),
                NotificationField("openiLinkContextToken", "Context Token", kind: .secure)
            ]
        ),
        NotificationChannel(
            type: "wpush",
            title: "WPush",
            symbol: "paperplane",
            fields: [
                NotificationField("wpushApiKey", "ApiKey", kind: .secure),
                NotificationField("wpushChannel", "Channel"),
                NotificationField("wpushTopicCode", "TopicCode")
            ]
        )
    ]

    static func channel(for type: String) -> NotificationChannel? {
        channels.first { $0.type == type }
    }

    static func title(for type: String) -> String {
        channel(for: type)?.title ?? type
    }
}
