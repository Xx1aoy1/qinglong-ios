//
//  CronViewManageView.swift
//  QingLong
//
//  视图管理：启用 / 停用、编辑、删除。系统视图只允许停用。
//

import SwiftUI

@MainActor
final class CronViewManageViewModel: ObservableObject {

    @Published var views: [QLCronView] = []
    @Published var state: LoadState = .idle
    @Published var busyIDs: Set<Int> = []

    var enabledCount: Int { views.filter(\.isEnabled).count }

    func load(session: AppSession, silent: Bool = false) async {
        if !silent, case .idle = state { state = .loading }
        do {
            views = try await CronViewService.list()
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            if apiError.isUnauthorized { session.handle(error); return }
            if !views.isEmpty {
                session.handle(error)
                return
            }
            state = .failed(apiError.localizedDescription)
        }
    }

    func setEnabled(_ view: QLCronView, enabled: Bool, session: AppSession) async {
        // 与面板一致：至少保留一个启用的视图
        if !enabled, view.isEnabled, enabledCount <= 1 {
            session.showToast("至少要保留一个启用的视图", tone: .warning)
            return
        }
        busyIDs.insert(view.id)
        defer { busyIDs.remove(view.id) }
        do {
            try await CronViewService.setEnabled(ids: [view.id], enabled: enabled)
            await load(session: session, silent: true)
            session.showToast(enabled ? "已显示该视图" : "已隐藏该视图", tone: .info)
        } catch {
            session.handle(error)
        }
    }

    func remove(_ view: QLCronView, session: AppSession) async {
        guard !view.isSystem else {
            session.showToast("内置视图不可删除", tone: .warning)
            return
        }
        busyIDs.insert(view.id)
        defer { busyIDs.remove(view.id) }
        do {
            try await CronViewService.remove(ids: [view.id])
            await load(session: session, silent: true)
            session.showToast("已删除视图", tone: .success)
        } catch {
            session.handle(error)
        }
    }
}

struct CronViewManageView: View {

    @EnvironmentObject private var session: AppSession
    @Environment(\.presentationMode) private var presentationMode

    @StateObject private var viewModel = CronViewManageViewModel()

    @State private var editingView: QLCronView?
    @State private var showsCreate = false
    @State private var pendingDelete: QLCronView?

    private let onChanged: () -> Void

    init(onChanged: @escaping () -> Void = {}) {
        self.onChanged = onChanged
    }

    var body: some View {
        NavigationView {
            content
                .navigationTitle("视图管理")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("完成") { presentationMode.wrappedValue.dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showsCreate = true
                        } label: {
                            Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                        }
                    }
                }
                .refreshable { await viewModel.load(session: session) }
                .task { await viewModel.load(session: session) }
                .sheet(isPresented: $showsCreate) {
                    CronViewEditorView(view: nil) { reload() }
                        .environmentObject(session)
                }
                .sheet(item: $editingView) { view in
                    CronViewEditorView(view: view) { reload() }
                        .environmentObject(session)
                }
                .alert(item: $pendingDelete) { view in
                    Alert(
                        title: Text("删除视图"),
                        message: Text("确定删除「\(view.name)」吗？任务本身不会受影响。"),
                        primaryButton: .destructive(Text("删除")) {
                            Task {
                                await viewModel.remove(view, session: session)
                                onChanged()
                            }
                        },
                        secondaryButton: .cancel(Text("取消"))
                    )
                }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading where viewModel.views.isEmpty:
            LoadingView(text: "读取视图…")
        case .failed(let message) where viewModel.views.isEmpty:
            ScrollView {
                EmptyStateView(
                    symbol: "slider.horizontal.3",
                    title: "无法读取视图",
                    message: message,
                    actionTitle: "重试"
                ) { Task { await viewModel.load(session: session) } }
            }
        default:
            if viewModel.views.isEmpty {
                ScrollView {
                    EmptyStateView(
                        symbol: "rectangle.stack.badge.plus",
                        title: "还没有视图",
                        message: "视图可以把常用筛选条件保存成标签页，例如「只看 GO-Script 任务」。",
                        actionTitle: "创建视图"
                    ) { showsCreate = true }
                }
            } else {
                list
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(viewModel.views) { view in
                    row(for: view)
                        .listRowBackground(Theme.surfaceElevated)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !view.isSystem {
                                Button(role: .destructive) {
                                    pendingDelete = view
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            if !view.isSystem {
                                Button {
                                    editingView = view
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(Theme.info)
                            }
                        }
                }
            } footer: {
                Text("停用的视图不会出现在任务列表顶部；至少需要保留一个启用的视图。面板内置视图只能停用，不能改名或删除。")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(for view: QLCronView) -> some View {
        HStack(spacing: Theme.Spacing.medium) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(view.name)
                        .font(Theme.Font.callout.weight(.medium))
                        .foregroundColor(view.isEnabled ? Theme.textPrimary : Theme.textTertiary)
                        .lineLimit(1)
                    if view.isSystem {
                        TagChip(text: "内置", color: Theme.info)
                    }
                    if !view.isEnabled {
                        TagChip(text: "已停用", color: Theme.textTertiary)
                    }
                }

                Text(view.conditionSummary)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(2)

                if !view.sortSummary.isEmpty {
                    Text("排序：\(view.sortSummary)")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if view.isSystem {
                    session.showToast("内置视图不可编辑", tone: .info)
                } else {
                    editingView = view
                }
            }

            if viewModel.busyIDs.contains(view.id) {
                ProgressView().scaleEffect(0.8)
            } else {
                Toggle("", isOn: Binding(
                    get: { view.isEnabled },
                    set: { value in
                        Task {
                            await viewModel.setEnabled(view, enabled: value, session: session)
                            onChanged()
                        }
                    }
                ))
                .labelsHidden()
            }
        }
        .padding(.vertical, 2)
    }

    private func reload() {
        Task {
            await viewModel.load(session: session, silent: true)
            onChanged()
        }
    }
}
