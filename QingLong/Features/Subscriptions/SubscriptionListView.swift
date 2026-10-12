//
//  SubscriptionListView.swift
//  QingLong
//
//  订阅管理：拉取脚本仓库 / 单文件，自动新增定时任务。
//

import SwiftUI
import UIKit

@MainActor
final class SubscriptionListViewModel: ObservableObject {

    @Published var items: [QLSubscription] = []
    @Published var keyword = ""
    @Published var statusFilter: EnvListViewModel.StatusFilter = .all
    @Published var state: LoadState = .idle
    @Published private(set) var busyIDs: Set<Int> = []

    var filtered: [QLSubscription] {
        var list = items
        switch statusFilter {
        case .all: break
        case .enabled: list = list.filter { $0.statusValue != .disabled }
        case .disabled: list = list.filter { $0.statusValue == .disabled }
        }
        return list.search(keyword)
    }

    func load(session: AppSession, silent: Bool = false) async {
        if !silent, case .idle = state { state = .loading }
        do {
            items = try await SubscriptionService.list()
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            if apiError.isUnauthorized { session.handle(error); return }
            state = .failed(apiError.localizedDescription)
        }
    }

    func perform(on item: QLSubscription, session: AppSession, _ action: @escaping () async throws -> Void) async {
        busyIDs.insert(item.id)
        defer { busyIDs.remove(item.id) }
        do {
            try await action()
            try? await Task.sleep(nanoseconds: 350_000_000)
            await load(session: session, silent: true)
        } catch {
            session.handle(error)
        }
    }
}

struct SubscriptionListView: View {

    @EnvironmentObject private var session: AppSession
    @StateObject private var viewModel = SubscriptionListViewModel()

    @State private var showsCreate = false
    @State private var editing: QLSubscription?
    @State private var pendingDelete: QLSubscription?

    var body: some View {
        content
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("订阅管理")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.keyword, prompt: "搜索别名 / 仓库地址")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showsCreate = true } label: {
                        Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            .refreshable { await viewModel.load(session: session) }
            .task { await viewModel.load(session: session) }
            .sheet(isPresented: $showsCreate) {
                SubscriptionEditView(target: .create).environmentObject(session)
            }
            .sheet(item: $editing) { item in
                SubscriptionEditView(target: .edit(item)).environmentObject(session)
            }
            .alert(item: $pendingDelete) { item in
                Alert(
                    title: Text("删除订阅"),
                    message: Text("确定删除「\(item.title)」吗？可选择同时删除它拉取到的脚本与任务。"),
                    primaryButton: .destructive(Text("仅删除订阅")) {
                        Task {
                            await viewModel.perform(on: item, session: session) {
                                try await SubscriptionService.remove(ids: [item.id], force: false)
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
            LoadingView(text: "加载订阅…")
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
                            symbol: viewModel.items.isEmpty ? "arrow.triangle.2.circlepath" : "magnifyingglass",
                            title: viewModel.items.isEmpty ? "还没有订阅" : "没有匹配的订阅",
                            message: viewModel.items.isEmpty
                                ? "订阅可以把脚本仓库（如各类签到脚本合集）自动同步到面板并创建定时任务。"
                                : "换个关键字试试。",
                            actionTitle: viewModel.items.isEmpty ? "添加订阅" : nil
                        ) { showsCreate = true }
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
                ForEach(EnvListViewModel.StatusFilter.allCases) { item in
                    FilterChip(
                        title: item.title,
                        count: item == .all ? viewModel.items.count : nil,
                        isSelected: viewModel.statusFilter == item
                    ) {
                        viewModel.statusFilter = item
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
                NavigationLink {
                    SubscriptionDetailView(item: item).environmentObject(session)
                } label: {
                    SubscriptionRow(item: item, isBusy: viewModel.busyIDs.contains(item.id))
                }
                .listRowBackground(Theme.surfaceElevated)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if item.statusValue == .running {
                        Button {
                            Task { await viewModel.perform(on: item, session: session) {
                                try await SubscriptionService.stop(ids: [item.id])
                            } }
                        } label: { Label("停止", systemImage: "stop.fill") }
                        .tint(Theme.danger)
                    } else {
                        Button {
                            Task {
                                await viewModel.perform(on: item, session: session) {
                                    try await SubscriptionService.run(ids: [item.id])
                                }
                                session.showToast("已触发拉取", tone: .success)
                            }
                        } label: { Label("拉取", systemImage: "arrow.down.circle.fill") }
                        .tint(Theme.success)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = item
                    } label: { Label("删除", systemImage: "trash") }

                    Button {
                        let enable = item.statusValue == .disabled
                        Task {
                            await viewModel.perform(on: item, session: session) {
                                try await SubscriptionService.setEnabled(ids: [item.id], enabled: enable)
                            }
                        }
                    } label: {
                        Label(item.statusValue == .disabled ? "启用" : "禁用",
                              systemImage: item.statusValue == .disabled ? "checkmark.circle" : "pause.circle")
                    }
                    .tint(item.statusValue == .disabled ? Theme.success : Theme.warning)
                }
                .contextMenu {
                    Button { editing = item } label: { Label("编辑", systemImage: "pencil") }
                    Button {
                        UIPasteboard.general.string = item.url
                        session.showToast("已复制仓库地址", tone: .success)
                    } label: { Label("复制地址", systemImage: "doc.on.doc") }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - 行

struct SubscriptionRow: View {
    let item: QLSubscription
    var isBusy: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.medium) {
            ZStack {
                Circle()
                    .fill(item.statusValue.tone.color.opacity(0.14))
                    .frame(width: 34, height: 34)
                if isBusy {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Image(systemName: item.statusValue == .running ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(item.statusValue.tone.color)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(Theme.Font.headline)
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    StatusPill(text: item.statusValue.title, tone: item.statusValue.tone, compact: true)
                }

                Text(item.url)
                    .font(Theme.Font.monoSmall)
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                WrapHStack(spacing: 5) {
                    TagChip(text: item.typeValue.title, color: Theme.info)
                    TagChip(text: item.scheduleDescription, color: Theme.brand)
                    if let branch = item.branch, !branch.isEmpty {
                        TagChip(text: branch, color: Theme.textSecondary)
                    }
                    if item.isAutoAddCron {
                        TagChip(text: "自动新增任务", color: Theme.success)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }
}
