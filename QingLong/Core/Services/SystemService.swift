//
//  SystemService.swift
//  QingLong
//

import Foundation

struct UpdateLogFrequencyPayload: Encodable { var logRemoveFrequency: Int? }
struct UpdateCronConcurrencyPayload: Encodable { var cronConcurrency: Int? }
struct UpdateDependenceProxyPayload: Encodable { var dependenceProxy: String? }
struct UpdateMirrorPayload: Encodable {
    var nodeMirror: String?
    var pythonMirror: String?
    var linuxMirror: String?
}
struct UpdateTimezonePayload: Encodable { var timezone: String? }
struct UpdateLanguagePayload: Encodable { var lang: String? }
struct UpdatePanelTitlePayload: Encodable { var panelTitle: String? }
struct UpdateSshKeyPayload: Encodable { var globalSshKey: String? }
struct CleanDependencePayload: Encodable { var type: String }
struct NotifyPayload: Encodable { var title: String; var content: String }
struct CommandRunPayload: Encodable { var command: String }
struct CommandStopPayload: Encodable { var command: String?; var pid: Int? }
struct ExportDataPayload: Encodable { var type: [String] }
struct ReloadPayload: Encodable { var type: String? }

enum SystemService {

    // MARK: - 配置读取

    static func config() async throws -> SystemConfig {
        try await APIClient.shared.send(Endpoint.get("/api/system/config"), as: SystemConfig.self)
    }

    // MARK: - 配置写入

    static func updateLogRemoveFrequency(_ value: Int?) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put("/api/system/config/log-remove-frequency", body: UpdateLogFrequencyPayload(logRemoveFrequency: value))
        )
    }

    static func updateCronConcurrency(_ value: Int?) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put("/api/system/config/cron-concurrency", body: UpdateCronConcurrencyPayload(cronConcurrency: value))
        )
    }

    static func updateDependenceProxy(_ value: String?) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put("/api/system/config/dependence-proxy", body: UpdateDependenceProxyPayload(dependenceProxy: value))
        )
    }

    /// Node 镜像切换会执行脚本，输出以流的形式返回
    static func updateNodeMirror(_ value: String?) -> AsyncThrowingStream<String, Error> {
        APIClient.shared.streamText(
            jsonEndpoint("/api/system/config/node-mirror", UpdateMirrorPayload(nodeMirror: value))
        )
    }

    /// Linux 镜像切换会执行脚本，输出以流的形式返回
    static func updateLinuxMirror(_ value: String?) -> AsyncThrowingStream<String, Error> {
        APIClient.shared.streamText(
            jsonEndpoint("/api/system/config/linux-mirror", UpdateMirrorPayload(linuxMirror: value))
        )
    }

    static func updatePythonMirror(_ value: String?) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put("/api/system/config/python-mirror", body: UpdateMirrorPayload(pythonMirror: value))
        )
    }

    static func updateTimezone(_ value: String?) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put("/api/system/config/timezone", body: UpdateTimezonePayload(timezone: value))
        )
    }

    static func updateLanguage(_ value: String?) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put("/api/system/config/lang", body: UpdateLanguagePayload(lang: value))
        )
    }

    static func updatePanelTitle(_ value: String?) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put("/api/system/config/panel-title", body: UpdatePanelTitlePayload(panelTitle: value))
        )
    }

    static func updateGlobalSshKey(_ value: String?) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put("/api/system/config/global-ssh-key", body: UpdateSshKeyPayload(globalSshKey: value))
        )
    }

    static func cleanDependence(type: String) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put("/api/system/config/dependence-clean", body: CleanDependencePayload(type: type))
        )
    }

    // MARK: - 面板运维

    static func checkUpdate() async throws -> UpdateCheckResult {
        try await APIClient.shared.send(
            Endpoint.put("/api/system/update-check", body: EmptyPayload()),
            as: UpdateCheckResult.self
        )
    }

    /// ⚠️ 触发面板自我更新（会重启容器）
    static func updatePanel() async throws {
        try await APIClient.shared.sendVoid(
            Endpoint.put("/api/system/update", body: EmptyPayload())
        )
    }

    static func reload(type: String? = nil) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put("/api/system/reload", body: ReloadPayload(type: type))
        )
    }

    static func notify(title: String, content: String) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put("/api/system/notify", body: NotifyPayload(title: title, content: content))
        )
    }

    // MARK: - 命令调试

    /// 执行任意命令并以流的方式返回输出
    static func runCommand(_ command: String) -> AsyncThrowingStream<String, Error> {
        APIClient.shared.streamText(
            jsonEndpoint("/api/system/command-run", CommandRunPayload(command: command))
        )
    }

    static func stopCommand(command: String? = nil, pid: Int? = nil) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put("/api/system/command-stop", body: CommandStopPayload(command: command, pid: pid))
        )
    }

    // MARK: - 数据备份

    /// 导出面板数据（tar.gz）
    static func exportData(types: [String]) async throws -> Data {
        try await APIClient.shared.download(
            try Endpoint.put("/api/system/data/export", body: ExportDataPayload(type: types))
        )
    }

    /// 导入面板数据（tar.gz）
    static func importData(_ data: Data, filename: String = "data.tgz") async throws {
        var form = MultipartFormData()
        form.appendFile(name: "data", filename: filename, mimeType: "application/gzip", data: data)
        try await APIClient.shared.sendVoid(Endpoint.multipart("/api/system/data/import", method: .put, form: form))
    }

    // MARK: - 系统日志

    static func systemLog(startTime: String? = nil, endTime: String? = nil, limit: Int? = nil) async throws -> String {
        try await APIClient.shared.sendText(
            Endpoint.get(
                "/api/system/log",
                query: [
                    "startTime": startTime,
                    "endTime": endTime,
                    "limit": limit.map(String.init),
                    "_t": String(Int(Date().timeIntervalSince1970))
                ]
            )
        )
    }

    static func deleteSystemLog() async throws {
        try await APIClient.shared.sendVoid(
            Endpoint(path: "/api/system/log", method: .delete)
        )
    }

    /// 重置面板鉴权信息（用户名 / 密码 / 重试次数 / 两步验证）
    static func resetAuth(
        username: String? = nil,
        password: String? = nil,
        retries: Int? = nil,
        twoFactorActivated: Bool? = nil
    ) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put(
                "/api/system/auth/reset",
                body: AuthResetRequest(
                    username: username,
                    password: password,
                    retries: retries,
                    twoFactorActivated: twoFactorActivated
                )
            )
        )
    }

    // MARK: - 开放接口应用

    static func apps() async throws -> [QLOpenApp] {
        try await APIClient.shared.sendArray(Endpoint.get("/api/apps"), as: QLOpenApp.self)
    }

    static func createApp(name: String, scopes: [String]) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.post("/api/apps", body: OpenAppPayload(id: nil, name: name, scopes: scopes))
        )
    }

    static func updateApp(id: Int, name: String, scopes: [String]) async throws {
        try await APIClient.shared.sendVoid(
            try Endpoint.put("/api/apps", body: OpenAppPayload(id: id, name: name, scopes: scopes))
        )
    }

    static func deleteApps(_ ids: [Int]) async throws {
        try await APIClient.shared.sendVoid(try Endpoint.delete("/api/apps", body: ids))
    }

    static func resetAppSecret(id: Int) async throws {
        try await APIClient.shared.sendVoid(
            Endpoint.put("/api/apps/\(id)/reset-secret", body: EmptyPayload())
        )
    }

    // MARK: - 内部

    /// 构造一个 JSON PUT 请求（用于流式接口，避免 `try` 污染调用点）
    private static func jsonEndpoint<T: Encodable>(_ path: String, _ body: T) -> Endpoint {
        Endpoint(
            path: path,
            method: .put,
            body: try? JSONCoder.encode(body),
            contentType: "application/json"
        )
    }
}
