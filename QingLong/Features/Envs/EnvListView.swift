//
//  EnvListView.swift
//  QingLong
//
//  环境变量管理：搜索、标签筛选、启用 / 禁用、置顶、批量操作、导入导出。
//

import SwiftUI
import UIKit

@MainActor
final class EnvListViewModel: ObservableObject {

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all, enabled, disabled

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "全部"
            case .enabled: return "已启用"
            case .disabled: return "已禁用"
            }
        }
    }

    @Published var envs: [QLEnv] = []
    @Published var keyword: String = ""
    @Published var selectedLabel: String?
    @Published var statusFilter: StatusFilter = .all
    @Published var state: LoadState = .idle
    @Published private(set) var busyIDs: Set<Int> = []
    @Published var isMultiSelecting = false
    @Published var selection: Set<Int> = []

    var labels: [String] { envs.allLabels }

    var filtered: [QLEnv] {
        var list = envs
        switch statusFilter {
        case .all: break
        case .enabled: list = list.filter { !$0.isDisabled }
        case .disabled: list = list.filter(\.isDisabled)
        }
        if let selectedLabel {
            list = list.filter { $0.labelList.contains(selectedLabel) }
        }
        list = list.search(keyword)
        let pinned = list.filter(\.isPinnedValue)
        let others = list.filter { !$0.isPinnedValue }
        return pinned + others
    }

    var enabledCount: Int { envs.filter { !$0.isDisabled }.count }
    var disabledCount: Int { envs.filter(\.isDisabled).count }

    func load(session: AppSession, silent: Bool = false) async {
        if !silent, case .idle = state { state = .loading }
        do {
            envs = try await EnvService.list()
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            if apiError.isUnauthorized { session.handle(error); return }
            state = .failed(apiError.localizedDescription)
        }
    }

    func perform(on ids: [Int], session: AppSession, refresh: Bool = true, _ action: @escaping () async throws -> Void) async {
        busyIDs.formUnion(ids)
        defer { busyIDs.subtract(ids) }
        do {
            try await action()
            if refresh {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await load(session: session, silent: true)
            }
        } catch {
            session.handle(error)
        }
    }
}

struct EnvListView: View {

    @EnvironmentObject private var session: AppSession
    @StateObject private var viewModel = EnvListViewModel()

    @State private var creating = false
    @State private var editingEnv: QLEnv?
    @State private var pendingDelete: [QLEnv] = []
    @State private var showsImport = false
    @State private var showsExport = false
    @State private var exportURL: URL?
    @State private var showsLabelEditor = false
    @State private var labelDraft = ""
    @State private var showsRename = false
    @State private var renameDraft = ""

    var body: some View {
        content
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("环境变量")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.keyword, prompt: "搜索变量名 / 值 / 备注")
            .toolbar { toolbar }
            .refreshable { await viewModel.load(session: session) }
            .task { await viewModel.load(session: session) }
            .sheet(isPresented: $creating) {
                EnvEditView(target: .create).environmentObject(session)
            }
            .sheet(item: $editingEnv) { env in
                EnvEditView(target: .edit(env)).environmentObject(session)
            }
            .sheet(isPresented: $showsImport) {
                EnvImportView().environmentObject(session)
            }
            .sheet(isPresented: $showsExport) {
                ShareSheet(items: exportURL.map { [$0] } ?? [])
            }
            .sheet(isPresented: $showsLabelEditor) {
                labelEditorSheet
            }
            .sheet(isPresented: $showsRename) {
                renameSheet
            }
            .alert(item: Binding(
                get: { pendingDelete.isEmpty ? nil : DeleteRequest(envs: pendingDelete) },
                set: { if $0 == nil { pendingDelete = [] } }
            )) { request in
                Alert(
                    title: Text("删除变量"),
                    message: Text("将删除 \(request.envs.count) 个环境变量，操作不可撤销。"),
                    primaryButton: .destructive(Text("删除")) {
                        let ids = request.envs.map(\.id)
                        Task {
                            await viewModel.perform(on: ids, session: session) {
                                try await EnvService.remove(ids: ids)
                            }
                            session.showToast("已删除 \(ids.count) 个变量", tone: .success)
                        }
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if viewModel.isMultiSelecting {
                Button("完成") {
                    viewModel.isMultiSelecting = false
                    viewModel.selection.removeAll()
                }
                .font(.system(size: 15, weight: .semibold))
            } else {
                Menu {
                    Button {
                        creating = true
                    } label: {
                        Label("新建变量", systemImage: "plus")
                    }
                    Button {
                        viewModel.isMultiSelecting = true
                    } label: {
                        Label("批量选择", systemImage: "checkmark.circle")
                    }
                    Divider()
                    Button {
                        showsImport = true
                    } label: {
                        Label("导入 JSON", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        Task { await exportEnvs() }
                    } label: {
                        Label("导出 JSON", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading where viewModel.envs.isEmpty:
            LoadingView(text: "加载环境变量…")
        case .failed(let message) where viewModel.envs.isEmpty:
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
                            symbol: viewModel.envs.isEmpty ? "shippingbox" : "magnifyingglass",
                            title: viewModel.envs.isEmpty ? "还没有环境变量" : "没有匹配的变量",
                            message: viewModel.envs.isEmpty
                                ? "环境变量用于存放账号、Cookie 等脚本运行时需要的配置。"
                                : "试试更换关键字或标签。",
                            actionTitle: viewModel.envs.isEmpty ? "新建变量" : nil
                        ) { creating = true }
                    }
                } else {
                    list
                }
                if viewModel.isMultiSelecting { batchBar }
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: Theme.Spacing.small) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.small) {
                    ForEach(EnvListViewModel.StatusFilter.allCases) { item in
                        FilterChip(
                            title: item.title,
                            count: count(for: item),
                            isSelected: viewModel.statusFilter == item
                        ) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                viewModel.statusFilter = item
                            }
                        }
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
        .padding(.vertical, Theme.Spacing.small)
    }

    private func count(for filter: EnvListViewModel.StatusFilter) -> Int? {
        switch filter {
        case .all: return viewModel.envs.count
        case .enabled: return viewModel.enabledCount
        case .disabled: return viewModel.disabledCount
        }
    }

    private var list: some View {
        List {
            ForEach(viewModel.filtered) { env in
                Group {
                    if viewModel.isMultiSelecting {
                        Button {
                            toggleSelection(env)
                        } label: {
                            HStack(spacing: Theme.Spacing.medium) {
                                Image(systemName: viewModel.selection.contains(env.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(viewModel.selection.contains(env.id) ? Theme.brand : Theme.textTertiary)
                                EnvRow(env: env, isBusy: viewModel.busyIDs.contains(env.id))
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            EnvDetailView(env: env).environmentObject(session)
                        } label: {
                            EnvRow(env: env, isBusy: viewModel.busyIDs.contains(env.id))
                        }
                    }
                }
                .listRowBackground(Theme.surfaceElevated)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = [env]
                    } label: {
                        Label("删除", systemImage: "trash")
                    }

                    Button {
                        Task {
                            await viewModel.perform(on: [env.id], session: session) {
                                try await EnvService.setEnabled(ids: [env.id], enabled: env.isDisabled)
                            }
                        }
                    } label: {
                        Label(env.isDisabled ? "启用" : "禁用", systemImage: env.isDisabled ? "checkmark.circle" : "pause.circle")
                    }
                    .tint(env.isDisabled ? Theme.success : Theme.warning)
                }
                .contextMenu {
                    Button {
                        editingEnv = env
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button {
                        Task {
                            await viewModel.perform(on: [env.id], session: session) {
                                try await EnvService.pin(ids: [env.id], pinned: !env.isPinnedValue)
                            }
                        }
                    } label: {
                        Label(env.isPinnedValue ? "取消置顶" : "置顶", systemImage: "pin")
                    }
                    Button {
                        UIPasteboard.general.string = env.value
                        session.showToast("已复制变量值", tone: .success)
                    } label: {
                        Label("复制值", systemImage: "doc.on.doc")
                    }
                    Button {
                        UIPasteboard.general.string = env.name
                        session.showToast("已复制变量名", tone: .success)
                    } label: {
                        Label("复制名称", systemImage: "textformat")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var batchBar: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Text("已选 \(viewModel.selection.count)")
                .font(Theme.Font.callout.weight(.medium))
                .foregroundColor(Theme.textSecondary)

            Spacer(minLength: 0)

            batchButton("启用", "checkmark.circle") {
                let ids = Array(viewModel.selection)
                Task {
                    await viewModel.perform(on: ids, session: session) {
                        try await EnvService.setEnabled(ids: ids, enabled: true)
                    }
                }
            }
            batchButton("禁用", "pause.circle") {
                let ids = Array(viewModel.selection)
                Task {
                    await viewModel.perform(on: ids, session: session) {
                        try await EnvService.setEnabled(ids: ids, enabled: false)
                    }
                }
            }
            batchButton("标签", "tag") {
                labelDraft = ""
                showsLabelEditor = true
            }
            batchButton("重命名", "pencil") {
                renameDraft = ""
                showsRename = true
            }
            batchButton("删除", "trash", tint: Theme.danger) {
                pendingDelete = viewModel.envs.filter { viewModel.selection.contains($0.id) }
            }
        }
        .padding(.horizontal, Theme.Spacing.large)
        .padding(.vertical, Theme.Spacing.small)
        .background(Theme.surfaceElevated)
        .overlay(Rectangle().fill(Theme.separator).frame(height: 0.6), alignment: .top)
    }

    private func batchButton(_ title: String, _ symbol: String, tint: Color = Theme.brand, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                Text(title).font(.system(size: 10))
            }
            .foregroundColor(viewModel.selection.isEmpty ? Theme.textTertiary : tint)
        }
        .buttonStyle(.pressable)
        .disabled(viewModel.selection.isEmpty)
    }

    private var labelEditorSheet: some View {
        NavigationView {
            Form {
                Section {
                    TextField("输入标签，多个用逗号分隔", text: $labelDraft)
                } header: {
                    SectionHeader(title: "编辑标签", subtitle: "作用于选中的 \(viewModel.selection.count) 个变量")
                }

                Section {
                    Button {
                        let labels = labelDraft
                            .replacingOccurrences(of: "，", with: ",")
                            .split(separator: ",")
                            .map { $0.trimmed }
                            .filter { !$0.isEmpty }
                        let ids = Array(viewModel.selection)
                        guard !labels.isEmpty, !ids.isEmpty else { return }
                        Task {
                            await viewModel.perform(on: ids, session: session) {
                                try await EnvService.addLabels(ids: ids, labels: labels)
                            }
                            showsLabelEditor = false
                            viewModel.selection.removeAll()
                        }
                    } label: {
                        Text("添加标签").foregroundColor(Theme.brand)
                    }

                    Button {
                        let labels = labelDraft
                            .replacingOccurrences(of: "，", with: ",")
                            .split(separator: ",")
                            .map { $0.trimmed }
                            .filter { !$0.isEmpty }
                        let ids = Array(viewModel.selection)
                        guard !labels.isEmpty, !ids.isEmpty else { return }
                        Task {
                            await viewModel.perform(on: ids, session: session) {
                                try await EnvService.removeLabels(ids: ids, labels: labels)
                            }
                            showsLabelEditor = false
                            viewModel.selection.removeAll()
                        }
                    } label: {
                        Text("移除标签").foregroundColor(Theme.danger)
                    }
                }
            }
            .navigationTitle("批量标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { showsLabelEditor = false }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var renameSheet: some View {
        NavigationView {
            Form {
                Section {
                    TextField("新的变量名", text: $renameDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(Theme.Font.mono)
                } header: {
                    SectionHeader(
                        title: "批量重命名",
                        subtitle: "将把选中的 \(viewModel.selection.count) 个变量的名称统一修改为该值"
                    )
                }
            }
            .navigationTitle("批量重命名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { showsRename = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("确定") {
                        let newName = renameDraft.trimmed
                        let ids = Array(viewModel.selection)
                        guard !newName.isEmpty, !ids.isEmpty else { return }
                        showsRename = false
                        Task {
                            await viewModel.perform(on: ids, session: session) {
                                try await EnvService.rename(ids: ids, name: newName)
                            }
                            viewModel.selection.removeAll()
                            session.showToast("已重命名 \(ids.count) 个变量", tone: .success)
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .disabled(renameDraft.trimmed.isEmpty || viewModel.selection.isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func toggleSelection(_ env: QLEnv) {
        if viewModel.selection.contains(env.id) {
            viewModel.selection.remove(env.id)
        } else {
            viewModel.selection.insert(env.id)
        }
    }

    private func exportEnvs() async {
        guard let data = try? EnvService.exportJSON(viewModel.envs) else {
            session.showToast("导出失败", tone: .danger)
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qinglong-envs-\(Int(Date().timeIntervalSince1970)).json")
        do {
            try data.write(to: url)
            exportURL = url
            showsExport = true
        } catch {
            session.showToast("写入导出文件失败", tone: .danger)
        }
    }
}

private struct DeleteRequest: Identifiable {
    let id = UUID()
    let envs: [QLEnv]
}

// MARK: - 行

struct EnvRow: View {
    let env: QLEnv
    var isBusy: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.medium) {
            ZStack {
                Circle()
                    .fill(env.isDisabled ? Theme.textTertiary.opacity(0.15) : Theme.success.opacity(0.14))
                    .frame(width: 32, height: 32)
                if isBusy {
                    ProgressView().scaleEffect(0.65)
                } else {
                    Image(systemName: env.isDisabled ? "eye.slash.fill" : "key.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(env.isDisabled ? Theme.textTertiary : Theme.success)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if env.isPinnedValue {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.warning)
                    }
                    Text(env.name)
                        .font(Theme.Font.headline)
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if env.isDisabled {
                        StatusPill(text: "已禁用", tone: .neutral, compact: true)
                    }
                }

                Text(env.maskedValue)
                    .font(Theme.Font.monoSmall)
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let remarks = env.remarks, !remarks.isEmpty {
                    Text(remarks)
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }

                if !env.labelList.isEmpty {
                    WrapHStack(spacing: 5) {
                        ForEach(env.labelList, id: \.self) { label in
                            TagChip(text: label)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }
}
