//
//  DependenceListView.swift
//  QingLong
//
//  依赖管理：Node.js / Python3 / Linux 依赖的安装、重装、卸载与日志查看。
//

import SwiftUI
import UIKit

@MainActor
final class DependenceListViewModel: ObservableObject {

    @Published var items: [QLDependence] = [] { didSet { recompute() } }
    @Published var keyword = "" { didSet { if keyword != oldValue { scheduleSearchRecompute() } } }
    @Published var typeFilter: DependenceType? { didSet { recompute() } }
    @Published var state: LoadState = .idle
    @Published private(set) var busyIDs: Set<Int> = []
    @Published var logTarget: QLDependence?

    /// 派生数据缓存：只在数据或筛选条件变化时重算，
    /// 否则每次渲染（含 4 秒轮询触发的刷新）都要重新过滤并扫描全表
    @Published private(set) var filtered: [QLDependence] = []
    @Published private(set) var hasBusy: Bool = false

    private var searchTask: Task<Void, Never>?
    private var lastLoadedAt: Date?

    init() {
        items = ListCache.dependences
        if !items.isEmpty { state = .loaded }
        recompute()
    }

    private func scheduleSearchRecompute() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            self?.recompute()
        }
    }

    private func recompute() {
        filtered = items.filtered(type: typeFilter).search(keyword)
        hasBusy = items.contains(where: \.isBusy)
    }

    /// 进入页面时刷新：短时间内已加载过就跳过，避免切 Tab 触发整表重建
    func loadIfStale(session: AppSession, maxAge: TimeInterval = 20) async {
        if !items.isEmpty, let last = lastLoadedAt, Date().timeIntervalSince(last) < maxAge {
            return
        }
        await load(session: session)
    }

    func load(session: AppSession, silent: Bool = false) async {
        if !silent, case .idle = state { state = .loading }
        do {
            items = try await DependenceService.list()
            lastLoadedAt = Date()
            ListCache.store(dependences: items)
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            if apiError.isUnauthorized { session.handle(error); return }
            state = .failed(apiError.localizedDescription)
        }
    }

    func perform(ids: [Int], session: AppSession, _ action: @escaping () async throws -> Void) async {
        busyIDs.formUnion(ids)
        defer { busyIDs.subtract(ids) }
        do {
            try await action()
            try? await Task.sleep(nanoseconds: 400_000_000)
            await load(session: session, silent: true)
        } catch {
            session.handle(error)
        }
    }
}

struct DependenceListView: View {

    @EnvironmentObject private var session: AppSession
    @StateObject private var viewModel = DependenceListViewModel()

    @State private var showsAdd = false
    @State private var newName = ""
    @State private var newType: DependenceType = .nodejs
    @State private var pendingDelete: QLDependence?

    var body: some View {
        content
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("依赖管理")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.keyword, prompt: "搜索依赖名称")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newName = ""
                        showsAdd = true
                    } label: {
                        Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            .refreshable { await viewModel.load(session: session) }
            .task {
                await viewModel.loadIfStale(session: session)
                // 有进行中的安装 / 卸载任务时，自动轮询刷新
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if Task.isCancelled { break }
                    guard viewModel.hasBusy else { continue }
                    await viewModel.load(session: session, silent: true)
                }
            }
            .sheet(isPresented: $showsAdd) { addSheet }
            .sheet(item: $viewModel.logTarget) { item in
                DependenceLogView(dependence: item).environmentObject(session)
            }
            .alert(item: $pendingDelete) { item in
                Alert(
                    title: Text("卸载依赖"),
                    message: Text("确定要卸载「\(item.name)」吗？"),
                    primaryButton: .destructive(Text("卸载")) {
                        Task {
                            await viewModel.perform(ids: [item.id], session: session) {
                                try await DependenceService.remove(ids: [item.id], force: true)
                            }
                        }
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading where viewModel.items.isEmpty:
            LoadingView(text: "加载依赖列表…")
        case .failed(let message) where viewModel.items.isEmpty:
            EmptyStateView(
                symbol: "wifi.exclamationmark",
                title: "加载失败",
                message: message,
                actionTitle: "重试"
            ) { Task { await viewModel.load(session: session) } }
        default:
            VStack(spacing: 0) {
                filterBar
                if viewModel.filtered.isEmpty {
                    ScrollView {
                        EmptyStateView(
                            symbol: viewModel.items.isEmpty ? "cube.box" : "magnifyingglass",
                            title: viewModel.items.isEmpty ? "还没有依赖" : "没有匹配的依赖",
                            message: viewModel.items.isEmpty
                                ? "依赖用于给脚本提供第三方库，例如 requests、axios 等。"
                                : "换个关键字或类型试试。",
                            actionTitle: viewModel.items.isEmpty ? "添加依赖" : nil
                        ) {
                            newName = ""
                            showsAdd = true
                        }
                    }
                } else {
                    list
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.small) {
                FilterChip(
                    title: "全部",
                    count: viewModel.items.count,
                    isSelected: viewModel.typeFilter == nil
                ) {
                    viewModel.typeFilter = nil
                }
                ForEach(DependenceType.allCases, id: \.self) { item in
                    FilterChip(
                        title: item.title,
                        count: viewModel.items.filter { $0.typeValue == item }.count,
                        isSelected: viewModel.typeFilter == item
                    ) {
                        viewModel.typeFilter = viewModel.typeFilter == item ? nil : item
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.large)
        }
        .padding(.vertical, Theme.Spacing.small)
    }

    private var list: some View {
        List {
            ForEach(viewModel.filtered) { item in
                DependenceRow(dependence: item, isBusy: viewModel.busyIDs.contains(item.id))
                    .listRowBackground(Theme.surfaceElevated)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.logTarget = item }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = item
                        } label: {
                            Label("卸载", systemImage: "trash")
                        }

                        Button {
                            Task {
                                await viewModel.perform(ids: [item.id], session: session) {
                                    try await DependenceService.reinstall(ids: [item.id])
                                }
                                session.showToast("已开始重新安装", tone: .info)
                            }
                        } label: {
                            Label("重装", systemImage: "arrow.clockwise")
                        }
                        .tint(Theme.info)
                    }
                    .contextMenu {
                        Button {
                            viewModel.logTarget = item
                        } label: {
                            Label("查看日志", systemImage: "doc.text")
                        }

                        Button {
                            Task {
                                await viewModel.perform(ids: [item.id], session: session) {
                                    try await DependenceService.reinstall(ids: [item.id])
                                }
                            }
                        } label: {
                            Label("重新安装", systemImage: "arrow.clockwise")
                        }

                        Button {
                            UIPasteboard.general.string = item.name
                            session.showToast("已复制依赖名", tone: .success)
                        } label: {
                            Label("复制名称", systemImage: "doc.on.doc")
                        }

                        if item.isBusy {
                            Divider()
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.perform(ids: [item.id], session: session) {
                                        try await DependenceService.cancel(ids: [item.id])
                                    }
                                }
                            } label: {
                                Label("取消任务", systemImage: "xmark.circle")
                            }
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var addSheet: some View {
        NavigationView {
            Form {
                Section {
                    TextField("依赖名称，例如 requests", text: $newName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(Theme.Font.mono)
                } header: {
                    SectionHeader(title: "依赖名称", subtitle: "支持带版本号，例如 requests==2.31.0")
                }

                Section {
                    Picker("依赖类型", selection: $newType) {
                        ForEach(DependenceType.allCases, id: \.self) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    SectionHeader(title: "运行环境")
                }
            }
            .navigationTitle("添加依赖")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { showsAdd = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("添加") {
                        let name = newName.trimmed
                        guard !name.isEmpty else { return }
                        showsAdd = false
                        Task {
                            do {
                                try await DependenceService.create(name: name, type: newType)
                                await viewModel.load(session: session, silent: true)
                                session.showToast("已提交安装：\(name)", tone: .success)
                            } catch {
                                session.handle(error)
                            }
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .disabled(newName.trimmed.isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - 行

struct DependenceRow: View {
    let dependence: QLDependence
    var isBusy: Bool = false

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Image(systemName: dependence.typeValue.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(dependence.typeValue.tone.color)
                .frame(width: 32, height: 32)
                .background(dependence.typeValue.tone.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(dependence.name)
                    .font(Theme.Font.callout.weight(.medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    TagChip(text: dependence.typeValue.shortTitle, color: dependence.typeValue.tone.color)
                    if let remark = dependence.remark, !remark.isEmpty {
                        Text(remark)
                            .font(Theme.Font.caption)
                            .foregroundColor(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            if isBusy {
                ProgressView().scaleEffect(0.75)
            } else {
                StatusPill(
                    text: dependence.statusValue.title,
                    tone: dependence.statusValue.tone,
                    compact: true
                )
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 依赖日志

struct DependenceLogView: View {

    let dependence: QLDependence

    @EnvironmentObject private var session: AppSession
    @State private var current: QLDependence?
    @State private var pollTask: Task<Void, Never>?

    private var item: QLDependence { current ?? dependence }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(item.logText.isEmpty ? "（暂无日志输出）" : item.logText)
                    .font(Theme.Font.monoSmall)
                    .foregroundColor(Theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.medium)
                    .id("dep-bottom")
            }
            .background(Theme.surfaceSunken.ignoresSafeArea())
            .onChange(of: item.log?.count ?? 0) { _ in
                guard item.isBusy else { return }
                withAnimation(.linear(duration: 0.12)) { proxy.scrollTo("dep-bottom", anchor: .bottom) }
            }
        }
        .navigationTitle("安装日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                StatusPill(text: item.statusValue.title, tone: item.statusValue.tone, compact: true)
            }
        }
        .task {
            await refresh()
            pollTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if Task.isCancelled { break }
                    guard item.isBusy else { continue }
                    await refresh()
                }
            }
        }
        .onDisappear { pollTask?.cancel() }
    }

    private func refresh() async {
        current = try? await DependenceService.detail(id: dependence.id)
    }
}
