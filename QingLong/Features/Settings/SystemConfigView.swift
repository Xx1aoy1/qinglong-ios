//
//  SystemConfigView.swift
//  QingLong
//
//  面板设置：标题、语言、时区、并发、清理频率、镜像源、SSH 密钥、面板更新。
//

import SwiftUI

@MainActor
final class SystemConfigViewModel: ObservableObject {

    @Published var info = SystemConfigInfo()
    @Published var state: LoadState = .idle
    @Published var isSaving = false
    @Published var updateResult: UpdateCheckResult?
    @Published var mirrorLog: String = ""
    @Published var showsMirrorLog = false
    @Published var isWorking = false

    // 编辑缓冲
    @Published var panelTitle = ""
    @Published var language = "zh_CN"
    @Published var timezone = "Asia/Shanghai"
    @Published var logRemoveFrequency = ""
    @Published var cronConcurrency = ""
    @Published var dependenceProxy = ""
    @Published var nodeMirror = ""
    @Published var pythonMirror = ""
    @Published var linuxMirror = ""
    @Published var globalSshKey = ""

    func load(session: AppSession) async {
        if info.panelTitle == nil { state = .loading }
        do {
            let config = try await SystemService.config()
            let value = config.infoOrEmpty
            info = value
            panelTitle = value.panelTitle ?? ""
            language = value.lang ?? "zh_CN"
            timezone = value.timezone ?? "Asia/Shanghai"
            logRemoveFrequency = value.logRemoveFrequency.map(String.init) ?? ""
            cronConcurrency = value.cronConcurrency.map(String.init) ?? ""
            dependenceProxy = value.dependenceProxy ?? ""
            nodeMirror = value.nodeMirror ?? ""
            pythonMirror = value.pythonMirror ?? ""
            linuxMirror = value.linuxMirror ?? ""
            globalSshKey = value.globalSshKey ?? ""
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            if apiError.isUnauthorized { session.handle(error); return }
            state = .failed(apiError.localizedDescription)
        }
    }

    func save(session: AppSession) async {
        isSaving = true
        defer { isSaving = false }
        do {
            if (info.panelTitle ?? "") != panelTitle {
                try await SystemService.updatePanelTitle(panelTitle.nilIfEmpty)
            }
            if (info.lang ?? "zh_CN") != language {
                try await SystemService.updateLanguage(language)
            }
            if (info.timezone ?? "Asia/Shanghai") != timezone {
                try await SystemService.updateTimezone(timezone)
            }
            let newFrequency = Int(logRemoveFrequency)
            if info.logRemoveFrequency != newFrequency {
                try await SystemService.updateLogRemoveFrequency(newFrequency)
            }
            let newConcurrency = Int(cronConcurrency)
            if info.cronConcurrency != newConcurrency {
                try await SystemService.updateCronConcurrency(newConcurrency)
            }
            if (info.dependenceProxy ?? "") != dependenceProxy {
                try await SystemService.updateDependenceProxy(dependenceProxy.nilIfEmpty)
            }
            if (info.pythonMirror ?? "") != pythonMirror {
                try await SystemService.updatePythonMirror(pythonMirror.nilIfEmpty)
            }
            if (info.globalSshKey ?? "") != globalSshKey {
                try await SystemService.updateGlobalSshKey(globalSshKey.nilIfEmpty)
            }
            await load(session: session)
            session.showToast("设置已保存", tone: .success)
        } catch {
            session.handle(error)
        }
    }

    /// Node / Linux 镜像切换会流式返回执行日志
    func applyMirror(kind: MirrorKind, session: AppSession) async {
        isWorking = true
        mirrorLog = ""
        showsMirrorLog = true
        defer { isWorking = false }

        let stream: AsyncThrowingStream<String, Error>
        switch kind {
        case .node:
            stream = SystemService.updateNodeMirror(nodeMirror.nilIfEmpty)
        case .linux:
            stream = SystemService.updateLinuxMirror(linuxMirror.nilIfEmpty)
        }

        do {
            for try await line in stream {
                mirrorLog += line + "\n"
            }
            mirrorLog += "\n—— 执行结束 ——"
            await load(session: session)
        } catch {
            mirrorLog += "\n[错误] \((error as? APIError)?.localizedDescription ?? error.localizedDescription)"
        }
    }

    enum MirrorKind: String, Identifiable {
        case node, linux
        var id: String { rawValue }
        var title: String { self == .node ? "Node 镜像" : "Linux 镜像" }
    }

    func checkUpdate(session: AppSession) async {
        isWorking = true
        defer { isWorking = false }
        do {
            updateResult = try await SystemService.checkUpdate()
            if let version = updateResult?.lastVersion {
                session.showToast("最新版本：\(version)", tone: .info)
            } else {
                session.showToast("已是最新版本", tone: .success)
            }
        } catch {
            session.handle(error)
        }
    }
}

struct SystemConfigView: View {

    @EnvironmentObject private var session: AppSession
    @StateObject private var viewModel = SystemConfigViewModel()

    @State private var showsReloadConfirm = false
    @State private var showsCleanDeps = false
    @State private var showsSshKeyEditor = false
    @State private var sshKeyDraft = ""

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading where viewModel.info.panelTitle == nil:
                LoadingView(text: "读取面板配置…")
            case .failed(let message) where viewModel.info.panelTitle == nil:
                ScrollView {
                    EmptyStateView(
                        symbol: "exclamationmark.triangle.fill",
                        title: "无法读取配置",
                        message: message,
                        actionTitle: "重试"
                    ) { Task { await viewModel.load(session: session) } }
                }
            default:
                form
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("面板设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") { Task { await viewModel.save(session: session) } }
                    .font(.system(size: 16, weight: .semibold))
                    .disabled(viewModel.isSaving)
            }
        }
        .refreshable { await viewModel.load(session: session) }
        .task { await viewModel.load(session: session) }
        .sheet(isPresented: $viewModel.showsMirrorLog) {
            mirrorLogSheet
        }
        .sheet(isPresented: $showsSshKeyEditor) {
            NavigationView {
                ZStack(alignment: .topLeading) {
                    if sshKeyDraft.isEmpty {
                        Text("-----BEGIN OPENSSH PRIVATE KEY-----")
                            .font(Theme.Font.monoSmall)
                            .foregroundColor(Theme.textTertiary)
                            .padding(Theme.Spacing.medium)
                    }
                    TextEditor(text: $sshKeyDraft)
                        .font(Theme.Font.monoSmall)
                        .padding(Theme.Spacing.small)
                }
                .background(Theme.surfaceSunken.ignoresSafeArea())
                .navigationTitle("全局 SSH 私钥")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("取消") { showsSshKeyEditor = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("保存") {
                            viewModel.globalSshKey = sshKeyDraft
                            showsSshKeyEditor = false
                        }
                        .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .navigationViewStyle(.stack)
        }
        .alert(isPresented: $showsReloadConfirm) {
            Alert(
                title: Text("重载面板"),
                message: Text("将重启面板内的服务进程，期间短暂无法访问。"),
                primaryButton: .destructive(Text("重载")) {
                    Task {
                        do {
                            try await SystemService.reload()
                            session.showToast("已触发重载", tone: .info)
                        } catch { session.handle(error) }
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .alert(isPresented: $showsCleanDeps) {
            Alert(
                title: Text("清理依赖缓存"),
                message: Text("将删除已卸载依赖的残留文件，释放磁盘空间。"),
                primaryButton: .destructive(Text("清理")) {
                    Task {
                        do {
                            try await SystemService.cleanDependence(type: "all")
                            session.showToast("已触发清理", tone: .info)
                        } catch { session.handle(error) }
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("面板标题", text: $viewModel.panelTitle)

                Picker("语言", selection: $viewModel.language) {
                    ForEach(SystemConfigInfo.commonLanguages, id: \.self) { Text($0).tag($0) }
                }

                Picker("时区", selection: $viewModel.timezone) {
                    ForEach(SystemConfigInfo.commonTimezones, id: \.self) { Text($0).tag($0) }
                }
            } header: {
                SectionHeader(title: "基础")
            }

            Section {
                TextField("日志清理频率（天，留空不清理）", text: $viewModel.logRemoveFrequency)
                    .keyboardType(.numberPad)
                TextField("任务并发数（留空使用默认）", text: $viewModel.cronConcurrency)
                    .keyboardType(.numberPad)
                TextField("依赖安装代理地址", text: $viewModel.dependenceProxy)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            } header: {
                SectionHeader(title: "任务与日志")
            } footer: {
                Text("并发数决定同一时刻最多运行多少条定时任务，数值越大对设备资源要求越高。")
                    .font(Theme.Font.caption)
            }

            Section {
                mirrorRow(
                    title: "Node 镜像",
                    value: $viewModel.nodeMirror,
                    presets: [
                        MirrorPreset(title: "npmmirror", value: "https://registry.npmmirror.com"),
                        MirrorPreset(title: "npm 官方", value: "https://registry.npmjs.org")
                    ],
                    kind: .node
                )

                mirrorRow(
                    title: "Linux 镜像",
                    value: $viewModel.linuxMirror,
                    presets: [
                        MirrorPreset(title: "阿里云", value: "mirrors.aliyun.com"),
                        MirrorPreset(title: "清华 TUNA", value: "mirrors.tuna.tsinghua.edu.cn"),
                        MirrorPreset(title: "腾讯云", value: "mirrors.cloud.tencent.com")
                    ],
                    kind: .linux
                )

                TextField("Python 镜像", text: $viewModel.pythonMirror)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(Theme.Font.monoSmall)

                HStack(spacing: 6) {
                    ForEach(Self.pythonMirrorPresets) { preset in
                        TagChip(text: preset.title, color: Theme.textSecondary) {
                            viewModel.pythonMirror = preset.value
                        }
                    }
                }
            } header: {
                SectionHeader(title: "镜像源", subtitle: "Node / Linux 切换会执行脚本，需等待输出完成")
            }

            Section {
                Button {
                    sshKeyDraft = viewModel.globalSshKey
                    showsSshKeyEditor = true
                } label: {
                    HStack {
                        Text("全局 SSH 私钥")
                        Spacer()
                        Text(viewModel.globalSshKey.isEmpty ? "未设置" : "已设置")
                            .foregroundColor(Theme.textTertiary)
                    }
                }
            } header: {
                SectionHeader(title: "私有仓库凭证")
            } footer: {
                Text("用于克隆私有仓库的订阅，保存后需要点右上角「保存」提交。")
                    .font(Theme.Font.caption)
            }

            Section {
                Button("清理依赖缓存") { showsCleanDeps = true }
                Button("重载面板服务") { showsReloadConfirm = true }
                Button("检查面板更新") {
                    Task { await viewModel.checkUpdate(session: session) }
                }

                if let result = viewModel.updateResult {
                    InfoRow(label: "当前版本", value: session.systemStatus?.version ?? "—")
                    InfoRow(label: "最新版本", value: result.lastVersion ?? "—",
                            valueColor: result.lastVersion == nil ? Theme.textSecondary : Theme.warning)
                    if let link = result.lastVersionLink, !link.isEmpty {
                        InfoRow(label: "更新说明", value: link)
                    }
                }
            } header: {
                SectionHeader(title: "维护")
            }
        }
        .listStyle(.insetGrouped)
        .overlay { if viewModel.isWorking { BlockingOverlay(text: "执行中…") } }
    }

    private static let pythonMirrorPresets: [MirrorPreset] = [
        MirrorPreset(title: "清华", value: "https://pypi.tuna.tsinghua.edu.cn/simple"),
        MirrorPreset(title: "阿里云", value: "https://mirrors.aliyun.com/pypi/simple")
    ]

    private func mirrorRow(
        title: String,
        value: Binding<String>,
        presets: [MirrorPreset],
        kind: SystemConfigViewModel.MirrorKind
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                Text(title)
                    .font(Theme.Font.callout)
                Spacer()
                Button("应用") {
                    Task { await viewModel.applyMirror(kind: kind, session: session) }
                }
                .font(Theme.Font.caption.weight(.semibold))
                .foregroundColor(Theme.brand)
            }

            TextField("镜像地址", text: value)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .font(Theme.Font.monoSmall)

            HStack(spacing: 6) {
                ForEach(presets) { preset in
                    TagChip(text: preset.title, color: Theme.textSecondary) {
                        value.wrappedValue = preset.value
                    }
                }
            }
        }
    }

    private var mirrorLogSheet: some View {
        NavigationView {
            ScrollView {
                Text(viewModel.mirrorLog.isEmpty ? "（等待输出…）" : viewModel.mirrorLog)
                    .font(Theme.Font.monoSmall)
                    .foregroundColor(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.medium)
                    .textSelection(.enabled)
            }
            .background(Theme.surfaceSunken.ignoresSafeArea())
            .navigationTitle("镜像切换输出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { viewModel.showsMirrorLog = false }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - 镜像预设

struct MirrorPreset: Identifiable, Hashable {
    let title: String
    let value: String

    var id: String { "\(title)|\(value)" }
}
