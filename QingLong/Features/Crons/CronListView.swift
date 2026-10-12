//
//  CronListView.swift
//  QingLong
//
//  定时任务列表：搜索、筛选、运行 / 停止 / 启用 / 禁用 / 置顶 / 删除。
//

import SwiftUI
import UIKit

@MainActor
final class CronListViewModel: ObservableObject {

    enum Filter: String, CaseIterable, Identifiable {
        case all, running, enabled, disabled, pinned, subscription

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "全部"
            case .running: return "运行中"
            case .enabled: return "已启用"
            case .disabled: return "已禁用"
            case .pinned: return "已置顶"
            case .subscription: return "订阅任务"
            }
        }
    }

    @Published var crons: [QLCron] = []
    @Published var keyword: String = ""
    @Published var filter: Filter = .all
    @Published var selectedLabel: String?
    @Published private(set) var busyIDs: Set<Int> = []
    @Published var state: LoadState = .idle

    var labels: [String] { crons.allLabels }

    var filtered: [QLCron] {
        var list = crons
        switch filter {
        case .all: break
        case .running: list = list.filter { $0.statusValue == .running || $0.statusValue == .queued }
        case .enabled: list = list.filter { $0.statusValue != .disabled }
        case .disabled: list = list.filter { $0.statusValue == .disabled }
        case .pinned: list = list.filter(\.isPinnedValue)
        case .subscription: list = list.filter(\.isFromSubscription)
        }
        if let selectedLabel {
            list = list.filter { $0.labelList.contains(selectedLabel) }
        }
        list = list.search(keyword)
        // 置顶优先，其次保持面板返回顺序
        let pinned = list.filter(\.isPinnedValue)
        let others = list.filter { !$0.isPinnedValue }
        return pinned + others
    }

    var runningCount: Int { crons.filter { $0.statusValue == .running }.count }

    func load(session: AppSession, silent: Bool = false) async {
        if !silent, case .idle = state { state = .loading }
        do {
            crons = try await CronService.list()
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

    /// 执行一个会改变任务状态的操作，并刷新列表
    func perform(
        on cron: QLCron,
        session: AppSession,
        _ action: @escaping () async throws -> Void
    ) async {
        busyIDs.insert(cron.id)
        defer { busyIDs.remove(cron.id) }
        do {
            try await action()
            try? await Task.sleep(nanoseconds: 350_000_000)
            await load(session: session, silent: true)
        } catch {
            session.handle(error)
        }
    }

    func run(_ cron: QLCron, session: AppSession) async {
        await perform(on: cron, session: session) { try await CronService.run(ids: [cron.id]) }
        session.showToast("已触发运行：\(cron.title)", tone: .success)
    }

    func stop(_ cron: QLCron, session: AppSession) async {
        await perform(on: cron, session: session) { try await CronService.stop(ids: [cron.id]) }
        session.showToast("已停止：\(cron.title)", tone: .warning)
    }

    func toggleEnabled(_ cron: QLCron, session: AppSession) async {
        let enable = cron.statusValue == .disabled
        await perform(on: cron, session: session) {
            try await CronService.setEnabled(ids: [cron.id], enabled: enable)
        }
        session.showToast(enable ? "已启用" : "已禁用", tone: enable ? .success : .info)
    }

    func togglePinned(_ cron: QLCron, session: AppSession) async {
        let pin = !cron.isPinnedValue
        await perform(on: cron, session: session) {
            try await CronService.setPinned(ids: [cron.id], pinned: pin)
        }
        session.showToast(pin ? "已置顶" : "已取消置顶", tone: .info)
    }

    func delete(_ cron: QLCron, session: AppSession) async {
        await perform(on: cron, session: session) { try await CronService.remove(ids: [cron.id]) }
        session.showToast("已删除：\(cron.title)", tone: .success)
    }
}

struct CronListView: View {

    @EnvironmentObject private var session: AppSession
    @StateObject private var viewModel = CronListViewModel()

    @State private var editingCron: QLCron?
    @State private var showsCreate = false
    @State private var pendingDelete: QLCron?

    init() {}

    var body: some View {
        content
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("定时任务")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.keyword, prompt: "搜索任务名 / 命令 / 标签")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showsCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            .refreshable { await viewModel.load(session: session) }
            .task { await viewModel.load(session: session) }
            .onChange(of: session.phase) { phase in
                if phase == .ready {
                    Task { await viewModel.load(session: session) }
                }
            }
            .sheet(isPresented: $showsCreate) {
                CronEditView(target: .create)
                    .environmentObject(session)
            }
            .sheet(item: $editingCron) { cron in
                CronEditView(target: .edit(cron))
                    .environmentObject(session)
            }
            .alert(item: $pendingDelete) { cron in
                Alert(
                    title: Text("删除任务"),
                    message: Text("确定要删除「\(cron.title)」吗？该操作不可撤销。"),
                    primaryButton: .destructive(Text("删除")) {
                        Task { await viewModel.delete(cron, session: session) }
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading where viewModel.crons.isEmpty:
            LoadingView(text: "加载任务列表…")

        case .failed(let message) where viewModel.crons.isEmpty:
            EmptyStateView(
                symbol: "wifi.exclamationmark",
                title: "加载失败",
                message: message,
                actionTitle: "重试"
            ) {
                Task { await viewModel.load(session: session) }
            }

        default:
            VStack(spacing: 0) {
                filterBar
                if viewModel.filtered.isEmpty {
                    ScrollView {
                        EmptyStateView(
                            symbol: viewModel.crons.isEmpty ? "clock.badge.questionmark" : "magnifyingglass",
                            title: viewModel.crons.isEmpty ? "还没有定时任务" : "没有匹配的任务",
                            message: viewModel.crons.isEmpty
                                ? "点击右上角「+」创建第一条任务，或先添加订阅自动同步脚本。"
                                : "试试更换筛选条件或关键字。",
                            actionTitle: viewModel.crons.isEmpty ? "新建任务" : nil
                        ) {
                            showsCreate = true
                        }
                    }
                } else {
                    list
                }
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: Theme.Spacing.small) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.small) {
                    ForEach(CronListViewModel.Filter.allCases) { item in
                        FilterChip(
                            title: item.title,
                            count: count(for: item),
                            isSelected: viewModel.filter == item
                        ) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                viewModel.filter = item
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.large)
            }

            if !viewModel.labels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.small) {
                        FilterChip(
                            title: "全部标签",
                            count: nil,
                            isSelected: viewModel.selectedLabel == nil
                        ) {
                            viewModel.selectedLabel = nil
                        }
                        ForEach(viewModel.labels, id: \.self) { label in
                            FilterChip(
                                title: label,
                                count: nil,
                                isSelected: viewModel.selectedLabel == label
                            ) {
                                viewModel.selectedLabel = viewModel.selectedLabel == label ? nil : label
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.large)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.small)
        .background(Theme.background)
    }

    private func count(for filter: CronListViewModel.Filter) -> Int? {
        switch filter {
        case .all: return viewModel.crons.count
        case .running: return viewModel.crons.filter { $0.statusValue == .running || $0.statusValue == .queued }.count
        case .enabled: return viewModel.crons.filter { $0.statusValue != .disabled }.count
        case .disabled: return viewModel.crons.filter { $0.statusValue == .disabled }.count
        case .pinned: return viewModel.crons.filter(\.isPinnedValue).count
        case .subscription: return viewModel.crons.filter(\.isFromSubscription).count
        }
    }

    private var list: some View {
        List {
            ForEach(viewModel.filtered) { cron in
                NavigationLink {
                    CronDetailView(cronID: cron.id)
                } label: {
                    CronRow(cron: cron, isBusy: viewModel.busyIDs.contains(cron.id))
                }
                .listRowBackground(Theme.surfaceElevated)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if cron.statusValue == .running {
                        Button {
                            Task { await viewModel.stop(cron, session: session) }
                        } label: {
                            Label("停止", systemImage: "stop.fill")
                        }
                        .tint(Theme.danger)
                    } else {
                        Button {
                            Task { await viewModel.run(cron, session: session) }
                        } label: {
                            Label("运行", systemImage: "play.fill")
                        }
                        .tint(Theme.success)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = cron
                    } label: {
                        Label("删除", systemImage: "trash")
                    }

                    Button {
                        Task { await viewModel.toggleEnabled(cron, session: session) }
                    } label: {
                        Label(
                            cron.statusValue == .disabled ? "启用" : "禁用",
                            systemImage: cron.statusValue == .disabled ? "checkmark.circle" : "pause.circle"
                        )
                    }
                    .tint(cron.statusValue == .disabled ? Theme.success : Theme.warning)
                }
                .contextMenu {
                    Button {
                        editingCron = cron
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }

                    Button {
                        Task { await viewModel.togglePinned(cron, session: session) }
                    } label: {
                        Label(cron.isPinnedValue ? "取消置顶" : "置顶", systemImage: "pin")
                    }

                    Button {
                        UIPasteboard.general.string = cron.command
                        session.showToast("已复制命令", tone: .success)
                    } label: {
                        Label("复制命令", systemImage: "doc.on.doc")
                    }

                    if cron.isFromSubscription {
                        Divider()
                        Label("来自订阅 #\(cron.sub_id ?? 0)", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - 行

struct CronRow: View {
    let cron: QLCron
    var isBusy: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.medium) {
            ZStack {
                Circle()
                    .fill(cron.statusValue.tone.color.opacity(0.14))
                    .frame(width: 34, height: 34)

                if isBusy {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(cron.statusValue.tone.color)
                } else {
                    Image(systemName: cron.statusValue.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(cron.statusValue.tone.color)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if cron.isPinnedValue {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.warning)
                    }
                    Text(cron.title)
                        .font(Theme.Font.headline)
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    StatusPill(
                        text: cron.statusValue.title,
                        tone: cron.statusValue.tone,
                        compact: true
                    )
                }

                HStack(spacing: 6) {
                    Label(cron.schedule ?? "—", systemImage: "calendar.badge.clock")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }

                Text(cron.command)
                    .font(Theme.Font.monoSmall)
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !cron.labelList.isEmpty {
                    WrapHStack(spacing: 5) {
                        ForEach(cron.labelList, id: \.self) { label in
                            TagChip(text: label, color: Theme.brand)
                        }
                    }
                }

                HStack(spacing: Theme.Spacing.small) {
                    Text("上次运行 \(cron.lastRunText)")
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.textTertiary)
                    if cron.isFromSubscription {
                        Text("· 订阅 #\(cron.sub_id ?? 0)")
                            .font(.system(size: 10.5))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 筛选胶囊

struct FilterChip: View {
    let title: String
    var count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                if let count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isSelected ? .white.opacity(0.85) : Theme.textTertiary)
                }
            }
            .foregroundColor(isSelected ? .white : Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Group {
                    if isSelected {
                        Capsule().fill(Theme.brandGradient)
                    } else {
                        Capsule().fill(Theme.surfaceElevated)
                            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 0.6))
                    }
                }
            )
        }
        .buttonStyle(.pressable)
    }
}
