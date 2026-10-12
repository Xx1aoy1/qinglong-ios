//
//  CronDetailView.swift
//  QingLong
//
//  任务详情：状态、命令、操作入口、历史日志。
//

import SwiftUI
import UIKit

@MainActor
final class CronDetailViewModel: ObservableObject {

    @Published private(set) var cron: QLCron?
    @Published private(set) var instances: [CronInstanceInfo] = []
    @Published var state: LoadState = .idle
    @Published var isWorking = false

    func load(id: Int, session: AppSession) async {
        if cron == nil { state = .loading }
        do {
            async let detail = CronService.detail(id: id)
            async let running = CronService.instances(id: id)
            cron = try await detail
            instances = try await running
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            if apiError.isUnauthorized {
                session.handle(error)
                return
            }
            state = .failed(apiError.localizedDescription)
        }
    }

    func perform(session: AppSession, _ action: @escaping () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await action()
            try? await Task.sleep(nanoseconds: 400_000_000)
            if let cron {
                await load(id: cron.id, session: session)
            }
        } catch {
            session.handle(error)
        }
    }
}

struct CronDetailView: View {

    let cronID: Int

    @EnvironmentObject private var session: AppSession
    @StateObject private var viewModel = CronDetailViewModel()

    @State private var showsEditor = false
    @State private var showsDeleteConfirm = false
    @State private var showsStopInstance: CronInstanceInfo?

    var body: some View {
        Group {
            if let cron = viewModel.cron {
                content(cron)
            } else if case .failed(let message) = viewModel.state {
                ScrollView {
                    EmptyStateView(
                        symbol: "wifi.exclamationmark",
                        title: "加载失败",
                        message: message,
                        actionTitle: "重试"
                    ) {
                        Task { await viewModel.load(id: cronID, session: session) }
                    }
                }
            } else {
                LoadingView(text: "读取任务详情…")
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(viewModel.cron?.title ?? "任务详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let cron = viewModel.cron {
                    Menu {
                        Button {
                            showsEditor = true
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }

                        Button {
                            UIPasteboard.general.string = cron.command
                            session.showToast("已复制命令", tone: .success)
                        } label: {
                            Label("复制命令", systemImage: "doc.on.doc")
                        }

                        Button {
                            Task {
                                await viewModel.perform(session: session) {
                                    try await CronService.setPinned(ids: [cron.id], pinned: !cron.isPinnedValue)
                                }
                            }
                        } label: {
                            Label(cron.isPinnedValue ? "取消置顶" : "置顶", systemImage: "pin")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showsDeleteConfirm = true
                        } label: {
                            Label("删除任务", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 15, weight: .semibold))
                    }
                }
            }
        }
        .task { await viewModel.load(id: cronID, session: session) }
        .refreshable { await viewModel.load(id: cronID, session: session) }
        .sheet(isPresented: $showsEditor) {
            if let cron = viewModel.cron {
                CronEditView(target: .edit(cron)).environmentObject(session)
            }
        }
        .alert(isPresented: $showsDeleteConfirm) {
            Alert(
                title: Text("删除任务"),
                message: Text("确定要删除该任务吗？该操作不可撤销。"),
                primaryButton: .destructive(Text("删除")) {
                    Task {
                        if let cron = viewModel.cron {
                            await viewModel.perform(session: session) {
                                try await CronService.remove(ids: [cron.id])
                            }
                            session.showToast("任务已删除", tone: .success)
                        }
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .overlay { if viewModel.isWorking { BlockingOverlay(text: "处理中…") } }
    }

    // MARK: - 内容

    private func content(_ cron: QLCron) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.large) {
                headerCard(cron)
                actionBar(cron)
                commandCard(cron)
                logSection(cron)
                infoCard(cron)
                dangerZone(cron)
            }
            .padding(Theme.Spacing.large)
        }
    }

    private func headerCard(_ cron: QLCron) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(spacing: Theme.Spacing.medium) {
                ZStack {
                    Circle()
                        .fill(cron.statusValue.tone.color.opacity(0.14))
                        .frame(width: 46, height: 46)
                    Image(systemName: cron.statusValue.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(cron.statusValue.tone.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(cron.title)
                        .font(Theme.Font.headline)
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        StatusPill(text: cron.statusValue.title, tone: cron.statusValue.tone, compact: true)
                        if cron.isPinnedValue {
                            StatusPill(text: "已置顶", tone: .warning, symbol: "pin.fill", compact: true)
                        }
                        if cron.isFromSubscription {
                            StatusPill(text: "订阅任务", tone: .info, symbol: "arrow.triangle.2.circlepath", compact: true)
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            if !cron.labelList.isEmpty {
                WrapHStack(spacing: 5) {
                    ForEach(cron.labelList, id: \.self) { label in
                        TagChip(text: label, color: Theme.brand)
                    }
                }
            }
        }
        .qlCard()
    }

    private func actionBar(_ cron: QLCron) -> some View {
        HStack(spacing: Theme.Spacing.medium) {
            ActionTile(
                title: cron.statusValue == .running ? "停止" : "运行",
                symbol: cron.statusValue == .running ? "stop.fill" : "play.fill",
                tone: cron.statusValue == .running ? .danger : .success
            ) {
                Task {
                    await viewModel.perform(session: session) {
                        if cron.statusValue == .running {
                            try await CronService.stop(ids: [cron.id])
                        } else {
                            try await CronService.run(ids: [cron.id])
                        }
                    }
                    session.showToast(cron.statusValue == .running ? "已发送停止指令" : "已触发运行", tone: .success)
                }
            }

            ActionTile(
                title: cron.statusValue == .disabled ? "启用" : "禁用",
                symbol: cron.statusValue == .disabled ? "checkmark.circle.fill" : "pause.circle.fill",
                tone: cron.statusValue == .disabled ? .success : .warning
            ) {
                let enable = cron.statusValue == .disabled
                Task {
                    await viewModel.perform(session: session) {
                        try await CronService.setEnabled(ids: [cron.id], enabled: enable)
                    }
                    session.showToast(enable ? "任务已启用" : "任务已禁用", tone: .info)
                }
            }

            ActionTile(title: "编辑", symbol: "pencil", tone: .info) {
                showsEditor = true
            }
        }
    }

    private func commandCard(_ cron: QLCron) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader(title: "执行命令")
            Text(cron.command)
                .font(Theme.Font.mono)
                .foregroundColor(Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.medium)
                .background(Theme.surfaceSunken)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        }
        .qlCard()
    }

    private func logSection(_ cron: QLCron) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(title: "日志")

            NavigationLink {
                LogConsoleView(title: "任务日志", subtitle: cron.title) { offset, limit, tail in
                    try await CronService.log(id: cron.id, offset: offset, limit: limit, tail: tail)
                }
                .environmentObject(session)
            } label: {
                NavigationRow(
                    symbol: "doc.text.magnifyingglass",
                    title: "实时日志",
                    subtitle: cron.log_path?.isEmpty == false ? cron.log_path : "查看最近一次运行的输出",
                    tone: .progress
                )
            }
            .buttonStyle(.pressable)

            NavigationLink {
                CronHistoryView(cron: cron).environmentObject(session)
            } label: {
                NavigationRow(
                    symbol: "clock.arrow.circlepath",
                    title: "历史日志",
                    subtitle: "按时间倒序查看历次运行记录",
                    tone: .info
                )
            }
            .buttonStyle(.pressable)

            if !viewModel.instances.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    SectionHeader(title: "运行实例", subtitle: "共 \(viewModel.instances.count) 条记录")
                    ForEach(viewModel.instances.prefix(5)) { instance in
                        InstanceRow(instance: instance) {
                            Task {
                                await viewModel.perform(session: session) {
                                    try await CronService.stopInstance(cronID: cron.id, instanceID: instance.id)
                                }
                            }
                        }
                    }
                }
                .qlCard()
            }
        }
    }

    private func infoCard(_ cron: QLCron) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader(title: "任务信息")
            InfoRow(label: "任务 ID", value: "\(cron.id)", mono: true)
            InfoRow(label: "定时规则", value: cron.schedule ?? "—", mono: true)
            InfoRow(label: "上次运行", value: cron.lastRunText)
            InfoRow(label: "上次完成", value: cron.lastFinishedText)
            InfoRow(label: "日志路径", value: cron.log_path ?? "—", mono: true)
            InfoRow(label: "工作目录", value: cron.work_dir ?? "—", mono: true)
            InfoRow(
                label: "多实例",
                value: cron.allow_multiple_instances == 1 ? "允许" : "不允许"
            )
            if let before = cron.task_before, !before.isEmpty {
                InfoRow(label: "前置命令", value: before, mono: true)
            }
            if let after = cron.task_after, !after.isEmpty {
                InfoRow(label: "后置命令", value: after, mono: true)
            }
            if let subID = cron.sub_id, subID > 0 {
                InfoRow(label: "来源订阅", value: "#\(subID)")
            }
        }
        .qlCard()
    }

    private func dangerZone(_ cron: QLCron) -> some View {
        Button(role: .destructive) {
            showsDeleteConfirm = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("删除任务")
            }
            .font(Theme.Font.callout.weight(.semibold))
            .foregroundColor(Theme.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.medium)
            .background(Theme.danger.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(cron.isSystemTask)
        .opacity(cron.isSystemTask ? 0.4 : 1)
    }
}

// MARK: - 子组件

struct ActionTile: View {
    let title: String
    let symbol: String
    let tone: StatusTone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(tone.color)
                Text(title)
                    .font(Theme.Font.caption.weight(.medium))
                    .foregroundColor(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.medium)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 0.6)
            )
        }
        .buttonStyle(.pressable)
    }
}

struct NavigationRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    var tone: StatusTone = .progress

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tone.color)
                .frame(width: 32, height: 32)
                .background(tone.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.callout.weight(.medium))
                    .foregroundColor(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(Theme.Spacing.medium)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 0.6)
        )
    }
}

struct InstanceRow: View {
    let instance: CronInstanceInfo
    var onStop: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            StatusPill(
                text: instance.isRunning ? "运行中" : "已结束",
                tone: instance.isRunning ? .progress : .neutral,
                compact: true
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(instance.startedText)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textSecondary)
                if let code = instance.exit_code {
                    Text("退出码 \(code)")
                        .font(Theme.Font.caption)
                        .foregroundColor(code == 0 ? Theme.success : Theme.danger)
                }
            }
            Spacer(minLength: 0)
            if instance.isRunning, let onStop {
                Button("停止", action: onStop)
                    .font(Theme.Font.caption.weight(.semibold))
                    .foregroundColor(Theme.danger)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 历史日志

struct CronHistoryView: View {

    let cron: QLCron

    @EnvironmentObject private var session: AppSession
    @State private var files: [CronLogFile] = []
    @State private var state: LoadState = .idle

    var body: some View {
        Group {
            switch state {
            case .loading where files.isEmpty:
                LoadingView(text: "读取历史日志…")
            case .failed(let message) where files.isEmpty:
                EmptyStateView(
                    symbol: "doc.questionmark",
                    title: "无法读取",
                    message: message,
                    actionTitle: "重试"
                ) { Task { await load() } }
            default:
                if files.isEmpty {
                    ScrollView {
                        EmptyStateView(
                            symbol: "tray",
                            title: "暂无历史日志",
                            message: "任务运行后，按小时切分的日志会出现在这里。"
                        )
                    }
                } else {
                    List {
                        ForEach(files) { file in
                            NavigationLink {
                                LogConsoleView(
                                    title: file.filename,
                                    subtitle: file.timeDescription
                                ) { offset, limit, tail in
                                    try await LogService.detail(
                                        path: normalizedDirectory(file.directory),
                                        file: file.filename,
                                        offset: offset,
                                        limit: limit,
                                        tail: tail
                                    )
                                }
                                .environmentObject(session)
                            } label: {
                                HStack(spacing: Theme.Spacing.medium) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 15))
                                        .foregroundColor(Theme.brand)
                                        .frame(width: 30)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.filename)
                                            .font(Theme.Font.monoSmall)
                                            .foregroundColor(Theme.textPrimary)
                                            .lineLimit(1)
                                        Text(file.timeDescription)
                                            .font(Theme.Font.caption)
                                            .foregroundColor(Theme.textTertiary)
                                    }
                                }
                            }
                            .listRowBackground(Theme.surfaceElevated)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("历史日志")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    /// 面板返回的 directory 形如 `/taskName`，去掉前导斜杠后作为 path 参数
    private func normalizedDirectory(_ raw: String?) -> String {
        var value = raw ?? ""
        while value.hasPrefix("/") { value.removeFirst() }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    private func load() async {
        if files.isEmpty { state = .loading }
        do {
            files = try await CronService.logFiles(id: cron.id)
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            if apiError.isUnauthorized { session.handle(error); return }
            state = .failed(apiError.localizedDescription)
        }
    }
}
