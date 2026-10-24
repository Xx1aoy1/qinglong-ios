//
//  ConfigFilesView.swift
//  QingLong
//
//  配置文件：面板 `config/` 目录下的 config.sh、extra.sh 等，可直接查看与编辑。
//

import SwiftUI
import UIKit

// MARK: - 列表

@MainActor
final class ConfigFilesViewModel: ObservableObject {

    @Published var files: [QLConfigFile] = [] { didSet { applyFilter() } }
    @Published var keyword: String = "" { didSet { if keyword != oldValue { applyFilter() } } }
    @Published var state: LoadState = .idle
    @Published private(set) var filtered: [QLConfigFile] = []

    func load(session: AppSession, silent: Bool = false) async {
        if !silent, case .idle = state { state = .loading }
        do {
            files = try await ConfigService.files()
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            if apiError.isUnauthorized { session.handle(error); return }
            if !files.isEmpty {
                session.handle(error)
                return
            }
            state = .failed(apiError.localizedDescription)
        }
    }

    private func applyFilter() {
        filtered = files.filtered(keyword: keyword)
    }
}

struct ConfigFilesView: View {

    @EnvironmentObject private var session: AppSession
    @StateObject private var viewModel = ConfigFilesViewModel()

    var body: some View {
        content
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("配置文件")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.keyword, prompt: "搜索配置文件名")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.load(session: session, silent: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .semibold))
                    }
                }
            }
            .refreshable { await viewModel.load(session: session) }
            .task { await viewModel.load(session: session) }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.files.isEmpty, case .loading = viewModel.state {
            LoadingView(text: "读取配置文件…")
        } else if viewModel.files.isEmpty, case .failed(let message) = viewModel.state {
            ScrollView {
                EmptyStateView(
                    symbol: "externaldrive.badge.questionmark",
                    title: "无法读取配置文件",
                    message: message,
                    actionTitle: "重试"
                ) { Task { await viewModel.load(session: session) } }
            }
        } else if viewModel.files.isEmpty {
            ScrollView {
                EmptyStateView(
                    symbol: "doc.text",
                    title: "配置目录为空",
                    message: "面板的 config 目录里还没有可编辑的文件，可以去网页端确认一下面板版本。"
                )
            }
        } else if viewModel.filtered.isEmpty {
            ScrollView {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "没有匹配的文件",
                    message: "换个关键字试试。"
                )
            }
        } else {
            list
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(viewModel.filtered) { file in
                    NavigationLink {
                        ConfigFileEditorView(file: file).environmentObject(session)
                    } label: {
                        ConfigFileRow(file: file)
                    }
                    .listRowBackground(Theme.surfaceElevated)
                }
            } header: {
                SectionHeader(title: "面板配置目录", subtitle: "共 \(viewModel.files.count) 个文件")
            } footer: {
                Text("这些文件位于面板的 config 目录，与网页端的「配置文件」页面是同一份内容。修改 config.sh 通常在下一次任务执行时生效，涉及环境变量的改动可能需要重启容器。")
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct ConfigFileRow: View {

    let file: QLConfigFile

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Image(systemName: file.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.brand)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.title)
                    .font(Theme.Font.callout)
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text(file.summary)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 编辑器

@MainActor
final class ConfigFileEditorViewModel: ObservableObject {

    /// 编辑框文本。**故意不用 @Published**：每敲一个字符都发通知会让整页重算、编辑区被
    /// 重新布局，光标容易跑。只有「是否已修改 / 字符数」真的变了才通知 UI。
    private(set) var content = ""
    private(set) var original = ""

    @Published var state: LoadState = .idle
    @Published var isSaving = false
    @Published private(set) var isDirty = false
    @Published private(set) var charCount = 0

    /// 已成功加载的文件路径。用于挡住重复拉取 —— 重复拉取会把编辑框里的内容顶回服务器版本，
    /// 表现为「刚删的字符又回来了 / 光标跑掉」。
    private var loadedPath: String?
    private var countTask: Task<Void, Never>?

    var hasChanges: Bool { content != original }

    /// 给编辑器用的绑定：写入绕开 @Published，不惊动整页刷新
    var textBinding: Binding<String> {
        Binding(
            get: { [weak self] in self?.content ?? "" },
            set: { [weak self] in self?.updateContent($0) }
        )
    }

    /// 编辑器每次输入都会走这里
    func updateContent(_ new: String) {
        guard new != content else { return }
        content = new

        // 脏标记只在 false/true 翻转时通知一次，连续输入不再重算页面
        let dirty = hasChanges
        if isDirty != dirty { isDirty = dirty }

        scheduleCountRefresh()
    }

    /// 字符数不必每个按键都算（`String.count` 是 O(n)），攒一下再刷
    private func scheduleCountRefresh() {
        countTask?.cancel()
        countTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 220_000_000) } catch { return }
            guard let self = self else { return }
            let count = self.content.count
            if self.charCount != count { self.charCount = count }
        }
    }

    func load(path: String, session: AppSession, force: Bool = false) async {
        if !force, loadedPath == path, case .loaded = state { return }
        state = .loading
        do {
            let text = try await ConfigService.content(path: path)
            content = text
            original = text
            charCount = text.count
            if isDirty { isDirty = false }
            loadedPath = path
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            if apiError.isUnauthorized { session.handle(error); return }
            state = .failed(apiError.localizedDescription)
        }
    }

    func save(name: String, session: AppSession) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await ConfigService.save(name: name, content: content)
            original = content
            if isDirty { isDirty = false }
            session.showToast("已保存 \(name)", tone: .success)
        } catch {
            session.handle(error)
        }
    }
}

struct ConfigFileEditorView: View {

    let file: QLConfigFile

    @EnvironmentObject private var session: AppSession
    @StateObject private var viewModel = ConfigFileEditorViewModel()
    @State private var shareItem: ShareItem?
    @State private var showsRevertConfirm = false

    init(file: QLConfigFile) {
        self.file = file
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                LoadingView(text: "读取配置文件…")
            case .failed(let message):
                ScrollView {
                    EmptyStateView(
                        symbol: "doc.questionmark",
                        title: "无法读取该文件",
                        message: message,
                        actionTitle: "重试"
                    ) { Task { await load() } }
                }
            default:
                editor
            }
        }
        .background(Theme.surfaceSunken.ignoresSafeArea())
        .navigationTitle(file.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: Theme.Spacing.small) {
                    Button {
                        UIPasteboard.general.string = viewModel.content
                        session.showToast("已复制文件内容", tone: .success)
                    } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 14, weight: .semibold))
                    }

                    Button {
                        Task { await viewModel.save(name: file.path, session: session) }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text(viewModel.isDirty ? "保存*" : "保存")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .disabled(viewModel.isSaving || !viewModel.isDirty)

                    Menu {
                        Button {
                            Task { await share() }
                        } label: { Label("导出到「文件」", systemImage: "square.and.arrow.up") }

                        Button {
                            if viewModel.isDirty {
                                showsRevertConfirm = true
                            } else {
                                Task { await load(force: true) }
                            }
                        } label: { Label("重新读取", systemImage: "arrow.clockwise") }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 15, weight: .semibold))
                    }
                }
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .alert("放弃未保存的修改？", isPresented: $showsRevertConfirm) {
            Button("重新读取", role: .destructive) { Task { await load(force: true) } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("重新读取会用服务器上的内容覆盖编辑框里尚未保存的文字。")
        }
        .task { await load() }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.small) {
                Image(systemName: file.symbol)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                Text(file.path)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if viewModel.isDirty {
                    StatusPill(text: "未保存", tone: .warning, symbol: "circle.fill", compact: true)
                }
                Text("\(viewModel.charCount) 字符")
                    .font(Theme.Font.caption)
                    .monospacedDigit()
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, 7)
            .background(Theme.surface)

            Divider().background(Theme.separator)

            // 用 UITextView 包装的编辑器：光标 / 滚动位置不会被输入回写顶掉
            CodeEditorView(text: viewModel.textBinding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load(force: Bool = false) async {
        await viewModel.load(path: file.path, session: session, force: force)
    }

    private func share() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.title)
        do {
            try viewModel.content.write(to: url, atomically: true, encoding: .utf8)
            shareItem = ShareItem(url: url)
        } catch {
            session.handle(error)
        }
    }
}
