//
//  CommandRunnerView.swift
//  QingLong
//
//  「命令调试」：在面板所在容器内执行 Shell 命令，并实时流式查看输出。
//  对应接口：PUT /api/system/command-run（流式）、PUT /api/system/command-stop
//

import SwiftUI
import UIKit

@MainActor
final class CommandRunnerViewModel: ObservableObject {

    struct Preset: Identifiable, Hashable {
        let title: String
        let command: String
        var id: String { command }
    }

    /// 常用命令预设（均基于青龙镜像的 alpine / debian 环境）
    static let presets: [Preset] = [
        Preset(title: "工作目录", command: "pwd && ls -la"),
        Preset(title: "磁盘占用", command: "df -h"),
        Preset(title: "内存占用", command: "free -m"),
        Preset(title: "系统信息", command: "cat /etc/os-release"),
        Preset(title: "Node 版本", command: "node -v && npm -v"),
        Preset(title: "Python 版本", command: "python3 -V && pip3 -V"),
        Preset(title: "占用 CPU 前十", command: "ps -eo pid,ppid,%cpu,%mem,cmd --sort=-%cpu | head -n 11"),
        Preset(title: "面板进程", command: "ps -ef | grep -i ql | grep -v grep"),
    ]

    @Published var command: String = ""
    @Published var output: String = ""
    @Published var isRunning: Bool = false
    @Published var autoScroll: Bool = true
    @Published var history: [String] = []

    private var runTask: Task<Void, Never>?
    private let historyKey = "qinglong.command.history"

    init() {
        history = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }

    var canRun: Bool { !command.trimmed.isEmpty && !isRunning }

    var outputSizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(output.utf8.count), countStyle: .file)
    }

    // MARK: - 执行

    func run(session: AppSession) {
        let cmd = command.trimmed
        guard !cmd.isEmpty, !isRunning else { return }

        output = ""
        isRunning = true
        remember(cmd)

        runTask?.cancel()
        runTask = Task { @MainActor in
            do {
                for try await line in SystemService.runCommand(cmd) {
                    if Task.isCancelled { break }
                    append(line + "\n")
                }
                if !Task.isCancelled {
                    if let code = lastExitCode(in: output) {
                        append("\n[进程已结束 · 退出码 \(code)]\n")
                    } else {
                        append("\n[进程已结束]\n")
                    }
                }
            } catch {
                let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
                if apiError == .cancelled {
                    append("\n[已取消]\n")
                } else if apiError.isUnauthorized {
                    session.handle(error)
                } else {
                    append("\n[执行失败] \(apiError.localizedDescription)\n")
                    session.showToast(apiError.localizedDescription, tone: .danger)
                }
            }
            isRunning = false
        }
    }

    func stop(session: AppSession) {
        guard isRunning else { return }
        let cmd = command.trimmed

        runTask?.cancel()
        runTask = nil
        isRunning = false
        append("\n[已请求终止]\n")

        Task { @MainActor in
            do {
                try await SystemService.stopCommand(command: cmd.isEmpty ? nil : cmd, pid: nil)
                session.showToast("已请求终止命令", tone: .warning)
            } catch {
                let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
                if apiError.isUnauthorized {
                    session.handle(error)
                } else {
                    session.showToast("终止失败：\(apiError.localizedDescription)", tone: .danger)
                }
            }
        }
    }

    func clear() {
        output = ""
    }

    // MARK: - 历史

    private func remember(_ command: String) {
        var list = history.filter { $0 != command }
        list.insert(command, at: 0)
        if list.count > 20 { list = Array(list.prefix(20)) }
        history = list
        UserDefaults.standard.set(list, forKey: historyKey)
    }

    func clearHistory() {
        history = []
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    // MARK: - 输出缓冲

    /// 追加输出，并限制内存占用（保留末尾 1MB）
    private func append(_ text: String) {
        output += text
        if output.utf8.count > 2 * 1024 * 1024 {
            let data = Data(output.utf8.suffix(1024 * 1024))
            output = String(data: data, encoding: .utf8) ?? String(output.suffix(400_000))
        }
    }

    /// 从输出尾部粗略提取 shell 退出码（若后端在日志中写入）
    private func lastExitCode(in text: String) -> Int? {
        guard let range = text.range(of: "exit code:", options: [.backwards, .caseInsensitive]) else {
            return nil
        }
        let tail = text[range.upperBound...].prefix(6)
        return Int(tail.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - 页面
struct CommandRunnerView: View {

    @EnvironmentObject private var session: AppSession
    @StateObject private var model = CommandRunnerViewModel()

    @State private var showsHistory = false
    @State private var showsShareSheet = false
    @State private var shareURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            inputArea
            Divider().background(Theme.separator)
            consoleArea
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("命令调试")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showsHistory = true
                    } label: {
                        Label("历史命令", systemImage: "clock.arrow.circlepath")
                    }

                    Button {
                        UIPasteboard.general.string = model.output
                        session.showToast("已复制输出", tone: .success)
                    } label: {
                        Label("复制输出", systemImage: "doc.on.doc")
                    }
                    .disabled(model.output.isEmpty)

                    Button {
                        exportOutput()
                    } label: {
                        Label("分享 / 导出", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.output.isEmpty)

                    Divider()

                    Button {
                        model.clearHistory()
                        session.showToast("已清空历史命令", tone: .info)
                    } label: {
                        Label("清空历史", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .sheet(isPresented: $showsHistory) { historySheet }
        .sheet(isPresented: $showsShareSheet) {
            ShareSheet(items: [shareURL].compactMap { $0 })
        }
    }

    // MARK: - 输入区

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            editor

            if !CommandRunnerViewModel.presets.isEmpty {
                WrapHStack(spacing: 6, lineSpacing: 6) {
                    ForEach(CommandRunnerViewModel.presets) { preset in
                        TagChip(text: preset.title, color: Theme.brand) {
                            model.command = preset.command
                        }
                    }
                }
            }

            actionRow
        }
        .padding(Theme.Spacing.large)
        .background(Theme.surface)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.command)
                .font(Theme.Font.mono)
                .foregroundColor(Theme.textPrimary)
                .frame(height: 92)
                .padding(Theme.Spacing.small)
                .background(Theme.surfaceSunken)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .stroke(model.command.isEmpty ? Theme.stroke : Theme.brand.opacity(0.5), lineWidth: 1)
                )
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(.asciiCapable)

            if model.command.isEmpty {
                Text("输入要执行的命令，例如 ls -la /ql/data")
                    .font(Theme.Font.mono)
                    .foregroundColor(Theme.textTertiary)
                    .padding(.horizontal, Theme.Spacing.medium)
                    .padding(.vertical, Theme.Spacing.medium)
                    .allowsHitTesting(false)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Button {
                model.run(session: session)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("执行")
                }
                .qlPrimaryButton(enabled: model.canRun)
            }
            .buttonStyle(.pressable)
            .disabled(!model.canRun)

            Button {
                model.stop(session: session)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("终止")
                }
                .font(Theme.Font.headline)
                .foregroundColor(model.isRunning ? Theme.danger : Theme.textTertiary)
                .frame(width: 104, height: 50)
                .background(model.isRunning ? Theme.danger.opacity(0.1) : Theme.surfaceSunken)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .buttonStyle(.pressable)
            .disabled(!model.isRunning)
        }
    }

    // MARK: - 输出区

    private var consoleArea: some View {
        VStack(spacing: 0) {
            consoleHeader
            Divider().background(Theme.separator)
            console
        }
        .frame(maxHeight: .infinity)
    }

    private var consoleHeader: some View {
        HStack(spacing: Theme.Spacing.medium) {
            HStack(spacing: 5) {
                Circle()
                    .fill(model.isRunning ? Theme.brand : Theme.textTertiary)
                    .frame(width: 7, height: 7)
                Text(model.isRunning ? "执行中" : "就绪")
                    .font(Theme.Font.caption.weight(.medium))
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer(minLength: 0)

            if !model.output.isEmpty {
                Text(model.outputSizeText)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textTertiary)
            }

            Button {
                model.autoScroll.toggle()
            } label: {
                Text(model.autoScroll ? "跟随输出" : "已暂停")
                    .font(Theme.Font.caption.weight(.semibold))
                    .foregroundColor(model.autoScroll ? Theme.brand : Theme.textTertiary)
            }
            .buttonStyle(.pressable)

            Button {
                model.clear()
            } label: {
                Text("清空")
                    .font(Theme.Font.caption.weight(.semibold))
                    .foregroundColor(model.output.isEmpty ? Theme.textTertiary : Theme.danger)
            }
            .buttonStyle(.pressable)
            .disabled(model.output.isEmpty)
        }
        .padding(.horizontal, Theme.Spacing.large)
        .padding(.vertical, Theme.Spacing.small)
        .background(Theme.surface)
    }

    private var console: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(model.output.isEmpty ? consolePlaceholder : model.output)
                    .font(Theme.Font.monoSmall)
                    .foregroundColor(model.output.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.medium)
                    .id("console-bottom")
            }
            .onChange(of: model.output.count) { _ in
                guard model.autoScroll, !model.output.isEmpty else { return }
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo("console-bottom", anchor: .bottom)
                }
            }
        }
        .background(Theme.surfaceSunken)
    }

    private var consolePlaceholder: String {
        """
        输出会实时显示在这里。

        说明：
        · 命令在面板所在容器内以面板进程权限执行（通常为 root）
        · 输出为流式增量推送，长任务可以随时点「终止」
        · 请勿执行删除数据目录等破坏性命令
        """
    }

    // MARK: - 历史命令

    private var historySheet: some View {
        NavigationView {
            Group {
                if model.history.isEmpty {
                    EmptyStateView(
                        symbol: "clock",
                        title: "暂无历史命令",
                        message: "执行过的命令会自动记录在这里"
                    )
                } else {
                    List {
                        ForEach(model.history, id: \.self) { item in
                            Button {
                                model.command = item
                                showsHistory = false
                            } label: {
                                HStack(spacing: Theme.Spacing.small) {
                                    Image(systemName: "terminal")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Theme.brand)
                                    Text(item)
                                        .font(Theme.Font.monoSmall)
                                        .foregroundColor(Theme.textPrimary)
                                        .lineLimit(2)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.pressable)
                        }
                        .onDelete { indexSet in
                            model.history.remove(atOffsets: indexSet)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("历史命令")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { showsHistory = false }
                        .font(Theme.Font.callout.weight(.semibold))
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 导出

    private func exportOutput() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("command-\(Int(Date().timeIntervalSince1970)).log")
        do {
            try model.output.write(to: url, atomically: true, encoding: .utf8)
            shareURL = url
            showsShareSheet = true
        } catch {
            session.showToast("导出失败：\(error.localizedDescription)", tone: .danger)
        }
    }
}
