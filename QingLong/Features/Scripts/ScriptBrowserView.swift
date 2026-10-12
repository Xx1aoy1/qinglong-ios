//
//  ScriptBrowserView.swift
//  QingLong
//
//  脚本文件管理。面板 `/api/scripts` 返回完整嵌套树，本地递归渲染即可。
//

import SwiftUI
import UIKit

@MainActor
final class ScriptBrowserViewModel: ObservableObject {

    @Published var tree: [QLFileItem] = []
    @Published var keyword = ""
    @Published var state: LoadState = .idle

    var filtered: [QLFileItem] { tree.filtered(keyword: keyword) }

    var fileCount: Int {
        func count(_ items: [QLFileItem]) -> Int {
            items.reduce(0) { partial, item in
                item.isFile ? partial + 1 : partial + count(item.children ?? [])
            }
        }
        return count(tree)
    }

    func load(session: AppSession, silent: Bool = false) async {
        if !silent, case .idle = state { state = .loading }
        do {
            tree = try await ScriptService.tree()
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            if apiError.isUnauthorized { session.handle(error); return }
            state = .failed(apiError.localizedDescription)
        }
    }
}

struct ScriptBrowserView: View {

    @EnvironmentObject private var session: AppSession
    @StateObject private var viewModel = ScriptBrowserViewModel()

    @State private var showsNewFile = false
    @State private var showsNewFolder = false
    @State private var newName = ""

    var body: some View {
        content
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("脚本管理")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.keyword, prompt: "搜索脚本文件名")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            newName = ""
                            showsNewFile = true
                        } label: { Label("新建文件", systemImage: "doc.badge.plus") }

                        Button {
                            newName = ""
                            showsNewFolder = true
                        } label: { Label("新建文件夹", systemImage: "folder.badge.plus") }

                        Divider()

                        Button {
                            Task { await viewModel.load(session: session) }
                        } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    } label: {
                        Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            .refreshable { await viewModel.load(session: session) }
            .task { await viewModel.load(session: session) }
            .sheet(isPresented: $showsNewFile) {
                PromptSheet(
                    title: "新建文件",
                    message: "将在脚本根目录创建，创建后可直接编辑内容。",
                    placeholder: "文件名，例如 demo.js",
                    text: $newName,
                    confirmTitle: "创建"
                ) { Task { await createFile() } }
            }
            .sheet(isPresented: $showsNewFolder) {
                PromptSheet(
                    title: "新建文件夹",
                    placeholder: "文件夹名",
                    text: $newName,
                    confirmTitle: "创建"
                ) { Task { await createFolder() } }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading where viewModel.tree.isEmpty:
            LoadingView(text: "读取脚本目录…")
        case .failed(let message) where viewModel.tree.isEmpty:
            EmptyStateView(
                symbol: "folder.badge.questionmark",
                title: "无法读取脚本目录",
                message: message,
                actionTitle: "重试"
            ) { Task { await viewModel.load(session: session) } }
        default:
            if viewModel.tree.isEmpty {
                ScrollView {
                    EmptyStateView(
                        symbol: "doc.text",
                        title: "脚本目录为空",
                        message: "可以新建脚本，或添加订阅自动同步脚本仓库。"
                    )
                }
            } else {
                List {
                    Section {
                        ForEach(viewModel.filtered) { item in
                            ScriptTreeRow(item: item)
                        }
                    } header: {
                        SectionHeader(title: "脚本目录", subtitle: "共 \(viewModel.fileCount) 个文件")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func createFile() async {
        let name = newName.trimmed
        guard !name.isEmpty else { return }
        do {
            try await ScriptService.save(filename: name, path: "", content: "", create: true)
            await viewModel.load(session: session, silent: true)
            session.showToast("已创建 \(name)", tone: .success)
        } catch {
            session.handle(error)
        }
    }

    private func createFolder() async {
        let name = newName.trimmed
        guard !name.isEmpty else { return }
        do {
            try await ScriptService.createDirectory(path: "", directory: name)
            await viewModel.load(session: session, silent: true)
            session.showToast("已创建文件夹 \(name)", tone: .success)
        } catch {
            session.handle(error)
        }
    }
}

// MARK: - 行

struct ScriptTreeRow: View {

    let item: QLFileItem

    @EnvironmentObject private var session: AppSession
    @State private var showsRename = false
    @State private var showsDelete = false
    @State private var renameDraft = ""

    var body: some View {
        if item.isDirectory {
            NavigationLink {
                ScriptDirectoryView(directory: item).environmentObject(session)
            } label: {
                rowContent
            }
            .listRowBackground(Theme.surfaceElevated)
        } else {
            NavigationLink {
                ScriptEditorView(file: item).environmentObject(session)
            } label: {
                rowContent
            }
            .listRowBackground(Theme.surfaceElevated)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { showsDelete = true } label: {
                    Label("删除", systemImage: "trash")
                }
            }
            .contextMenu {
                Button { renameDraft = item.title; showsRename = true } label: {
                    Label("重命名", systemImage: "pencil")
                }
                Button {
                    UIPasteboard.general.string = item.key
                    session.showToast("已复制路径", tone: .success)
                } label: {
                    Label("复制路径", systemImage: "doc.on.doc")
                }
            }
            .sheet(isPresented: $showsRename) {
                PromptSheet(
                    title: "重命名",
                    placeholder: "新的文件名",
                    text: $renameDraft
                ) { Task { await rename() } }
            }
            .alert("删除文件", isPresented: $showsDelete) {
                Button("删除", role: .destructive) { Task { await remove() } }
                Button("取消", role: .cancel) {}
            } message: {
                Text("确定删除「\(item.title)」吗？该操作不可撤销。")
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Image(systemName: ScriptFileKind.symbol(for: item))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(item.isDirectory ? Theme.warning : Theme.brand)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.Font.callout)
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let count = item.children?.count, item.isDirectory {
                        Text("\(count) 项")
                    } else if !item.sizeText.isEmpty {
                        Text(item.sizeText)
                    }
                    if !item.createTimeText.isEmpty {
                        Text("·")
                        Text(item.createTimeText)
                    }
                }
                .font(Theme.Font.caption)
                .foregroundColor(Theme.textTertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func rename() async {
        let newName = renameDraft.trimmed
        guard !newName.isEmpty, newName != item.title else { return }
        do {
            try await ScriptService.rename(path: item.parent ?? "", filename: item.title, newFilename: newName)
            session.showToast("已重命名", tone: .success)
        } catch {
            session.handle(error)
        }
    }

    private func remove() async {
        do {
            try await ScriptService.remove(path: item.parent ?? "", filename: item.title)
            session.showToast("已删除", tone: .success)
        } catch {
            session.handle(error)
        }
    }
}

/// 子目录
struct ScriptDirectoryView: View {

    let directory: QLFileItem

    @EnvironmentObject private var session: AppSession

    private var children: [QLFileItem] {
        (directory.children ?? []).sortedForDisplay
    }

    var body: some View {
        List {
            if children.isEmpty {
                Text("该目录为空")
                    .font(Theme.Font.callout)
                    .foregroundColor(Theme.textTertiary)
                    .listRowBackground(Theme.surfaceElevated)
            } else {
                ForEach(children) { item in
                    ScriptTreeRow(item: item)
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(directory.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
