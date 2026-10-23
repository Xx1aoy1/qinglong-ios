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

    @Published var crons: [QLCron] = [] { didSet { recompute() } }
    @Published var keyword: String = "" { didSet { if keyword != oldValue { scheduleSearchRecompute() } } }
    @Published var filter: Filter = .all { didSet { recompute() } }
    @Published var selectedLabel: String? { didSet { recompute() } }
    @Published private(set) var busyIDs: Set<Int> = []
    @Published var state: LoadState = .idle

    // MARK: - 视图（面板侧的分组标签页）

    @Published private(set) var views: [QLCronView] = [] { didSet { recompute() } }
    @Published var selectedViewID: Int? { didSet { if selectedViewID != oldValue { recompute() } } }
    /// 面板版本过低（没有 /api/crons/views）时隐藏整条视图栏
    @Published private(set) var viewsAvailable = true

    /// 只展示启用中的非内置视图；内置的「全部任务」由最左侧固定标签代表
    var viewTabs: [QLCronView] {
        views.filter { $0.isEnabled && !$0.isSystem }
    }

    private var activeView: QLCronView? {
        guard let selectedViewID else { return nil }
        return views.first { $0.id == selectedViewID && $0.isEnabled }
    }

    /// 当前选中的视图（供「编辑当前视图」入口使用）
    var activeViewForEditing: QLCronView? { activeView }

    /// 派生数据统一缓存：只在 crons / 筛选条件变化时重算一次。
    /// 之前 filtered、labels、各筛选项计数都是计算属性，会在每次渲染时
    /// 反复做 O(n log n) 的过滤排序（一个页面动辄重算十几次），列表越大越卡。
    @Published private(set) var filtered: [QLCron] = []
    @Published private(set) var labels: [String] = []
    @Published private(set) var filterCounts: [Filter: Int] = [:]

    private var searchTask: Task<Void, Never>?

    init() {
        // 命中进程内缓存时先直接出内容，随后由页面静默刷新
        crons = ListCache.crons
        if !crons.isEmpty { state = .loaded }
        recompute()
    }

    func count(for filter: Filter) -> Int { filterCounts[filter] ?? 0 }

    var runningCount: Int { filterCounts[.running] ?? 0 }

    /// 搜索输入做 180ms 防抖，避免每敲一个字都重排整个列表
    private func scheduleSearchRecompute() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            self?.recompute()
        }
    }

    private func recompute() {
        // 视图条件先求值，后面的状态胶囊 / 标签 / 关键字都在视图范围内继续收窄，
        // 这样胶囊上的计数与用户看到的列表始终一致。
        let scoped = activeView.map { crons.applying($0) } ?? crons

        var counts: [Filter: Int] = [:]
        counts[.all] = scoped.count
        var running = 0, enabled = 0, disabled = 0, pinned = 0, subscription = 0
        var labelSet = Set<String>()
        for cron in scoped {
            switch cron.statusValue {
            case .running, .queued: running += 1
            case .disabled: disabled += 1
            default: break
            }
            if cron.statusValue != .disabled { enabled += 1 }
            if cron.isPinnedValue { pinned += 1 }
            if cron.isFromSubscription { subscription += 1 }
            for label in cron.labelList { labelSet.insert(label) }
        }
        counts[.running] = running
        counts[.enabled] = enabled
        counts[.disabled] = disabled
        counts[.pinned] = pinned
        counts[.subscription] = subscription
        filterCounts = counts
        labels = labelSet.sorted()

        var list = scoped
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
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyword.isEmpty {
            list = list.search(trimmedKeyword)
        }
        // 视图自带排序时以它的顺序为准；否则置顶优先，其次保持面板返回顺序
        if let view = activeView, view.hasSorts {
            filtered = list
        } else {
            let pinnedList = list.filter(\.isPinnedValue)
            let others = list.filter { !$0.isPinnedValue }
            filtered = pinnedList + others
        }
    }

    func load(session: AppSession, silent: Bool = false) async {
        if !silent, case .idle = state { state = .loading }
        do {
            crons = try await CronService.list()
            ListCache.store(crons: crons)
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            if apiError.isUnauthorized {
                session.handle(error)
                return
            }
            // 已有缓存内容时不要把整页换成错误页，只提示一下
            if !crons.isEmpty {
                session.handle(error)
                return
            }
            state = .failed(apiError.localizedDescription)
        }
    }

    /// 进入页面时的刷新：短时间内已经加载过就跳过，
    /// 避免每次切 Tab 都重新请求并整表重建（这是"卡一下"的主要来源之一）。
    /// 已有缓存但已过期时走静默刷新，页面不会闪一下 loading。
    /// 下拉刷新与操作后的刷新仍走 load(...)，不受影响。
    func loadIfStale(session: AppSession, maxAge: TimeInterval = 60) async {
        // 视图列表很轻，每次进页面顺带刷新一次；失败（旧面板没有该接口）时隐藏视图栏
        await loadViews(session: session)
        if !crons.isEmpty {
            if let last = ListCache.lastLoaded(.crons),
               Date().timeIntervalSince(last) < maxAge {
                return
            }
            await load(session: session, silent: true)
            return
        }
        await load(session: session)
    }

    // MARK: - 视图

    func loadViews(session: AppSession) async {
        do {
            views = try await CronViewService.list()
            viewsAvailable = true
            // 选中的视图被停用 / 删除后回到「全部任务」
            if let selectedViewID, !views.contains(where: { $0.id == selectedViewID && $0.isEnabled }) {
                self.selectedViewID = nil
            }
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            if apiError.isUnauthorized { session.handle(error); return }
            viewsAvailable = false
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

    @State private var showsCreateView = false
    @State private var showsManageViews = false
    @State private var editingView: QLCronView?

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
            .refreshable {
                await viewModel.loadViews(session: session)
                await viewModel.load(session: session)
            }
            .task { await viewModel.loadIfStale(session: session) }
            .onChange(of: session.phase) { phase in
                if phase == .ready {
                    Task {
                        await viewModel.loadViews(session: session)
                        await viewModel.load(session: session)
                    }
                }
            }
            .sheet(isPresented: $showsCreateView) {
                CronViewEditorView(view: nil) { reloadViews() }
                    .environmentObject(session)
            }
            .sheet(item: $editingView) { view in
                CronViewEditorView(view: view) { reloadViews() }
                    .environmentObject(session)
            }
            .sheet(isPresented: $showsManageViews) {
                CronViewManageView { reloadViews() }
                    .environmentObject(session)
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
        // 先把筛选栏渲染出来：首次加载（没有缓存）时只有下半部分在转圈，
        // 标题栏与筛选栏立即可见，不会有整页被 loading 顶掉的"卡一下"。
        VStack(spacing: 0) {
            filterBar
            contentBody
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        if viewModel.crons.isEmpty, case .loading = viewModel.state {
            VStack {
                Spacer(minLength: 0)
                LoadingView(text: "正在同步任务列表…")
                Spacer(minLength: 0)
            }
        } else if viewModel.crons.isEmpty, case .failed(let message) = viewModel.state {
            ScrollView {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: "加载失败",
                    message: message,
                    actionTitle: "重试"
                ) {
                    Task { await viewModel.load(session: session) }
                }
            }
        } else if viewModel.filtered.isEmpty {
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

    private var filterBar: some View {
        VStack(spacing: Theme.Spacing.small) {
            if viewModel.viewsAvailable {
                viewTabsRow
            }
            statusRow
            if !viewModel.labels.isEmpty {
                labelsRow
            }
        }
        .padding(.vertical, Theme.Spacing.small)
        .background(Theme.background)
    }

    // MARK: - 视图标签栏

    private var viewTabsRow: some View {
        HStack(spacing: Theme.Spacing.small) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.small) {
                    FilterChip(
                        title: "全部任务",
                        count: nil,
                        isSelected: viewModel.selectedViewID == nil
                    ) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            viewModel.selectedViewID = nil
                        }
                    }

                    ForEach(viewModel.viewTabs) { view in
                        FilterChip(
                            title: view.name,
                            count: nil,
                            isSelected: viewModel.selectedViewID == view.id
                        ) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                viewModel.selectedViewID = viewModel.selectedViewID == view.id ? nil : view.id
                            }
                        }
                    }
                }
                .padding(.leading, Theme.Spacing.large)
                .padding(.trailing, Theme.Spacing.small)
            }

            viewMenu
                .padding(.trailing, Theme.Spacing.medium)
        }
    }

    private var viewMenu: some View {
        Menu {
            Button {
                showsCreateView = true
            } label: {
                Label("创建视图", systemImage: "plus.circle")
            }

            Button {
                showsManageViews = true
            } label: {
                Label("视图管理", systemImage: "slider.horizontal.3")
            }

            if let view = viewModel.activeViewForEditing {
                Divider()
                Button {
                    editingView = view
                } label: {
                    Label("编辑「\(view.name)」", systemImage: "pencil")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.surfaceElevated))
                .overlay(Circle().stroke(Theme.stroke, lineWidth: 0.6))
        }
    }

    private var statusRow: some View {
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
    }

    private var labelsRow: some View {
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

    private func count(for filter: CronListViewModel.Filter) -> Int? {
        // 计数在 ViewModel 里一次算好，这里不再逐项过滤
        viewModel.count(for: filter)
    }

    /// 视图增删改后重新拉取标签页，并让列表按新条件重新求值
    private func reloadViews() {
        Task { await viewModel.loadViews(session: session) }
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

    /// 标签在行内只展示前两个，避免自定义 Layout 逐行测量带来的滚动开销
    private var rowLabels: [String] { cron.labelList }

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

                if !rowLabels.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(rowLabels.prefix(2), id: \.self) { label in
                            TagChip(text: label, color: Theme.brand)
                        }
                        if rowLabels.count > 2 {
                            Text("+\(rowLabels.count - 2)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Theme.textTertiary)
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
