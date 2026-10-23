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

    @Published var content = ""
    @Published var original = ""
    @Published var state: LoadState = .idle
    @Published var isSaving = false

    var hasChanges: Bool { content != original }

    func load(path: String, session: AppSession) async {
        state = .loading
        do {
            let text = try await ConfigService.content(path: path)
            content = text
            original = text
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
                            Text(viewModel.hasChanges ? "保存*" : "保存")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .disabled(viewModel.isSaving || !viewModel.hasChanges)

                    Menu {
                        Button {
                            Task { await share() }
                        } label: { Label("导出到「文件」", systemImage: "square.and.arrow.up") }

                        Button {
                            Task { await load() }
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
                if viewModel.hasChanges {
                    StatusPill(text: "未保存", tone: .warning, symbol: "circle.fill", compact: true)
                }
                Text("\(viewModel.content.count) 字符")
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, 7)
            .background(Theme.surface)

            Divider().background(Theme.separator)

            TextEditor(text: $viewModel.content)
                .font(Theme.Font.mono)
                .foregroundColor(Theme.textPrimary)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, Theme.Spacing.small)
                .background(Theme.surfaceSunken)
        }
    }

    private func load() async {
        await viewModel.load(path: file.path, session: session)
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
