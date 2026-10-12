//
//  LogBrowserView.swift
//  QingLong
//
//  日志文件浏览。面板 `/api/logs` 一次性返回完整嵌套目录树，因此本地递归即可，无需重复请求。
//

import SwiftUI
import UIKit

struct LogBrowserView: View {

    @EnvironmentObject private var session: AppSession
    @State private var tree: [QLFileItem] = []
    @State private var state: LoadState = .idle
    @State private var keyword = ""

    private var filtered: [QLFileItem] {
        tree.filtered(keyword: keyword)
    }

    var body: some View {
        Group {
            switch state {
            case .loading where tree.isEmpty:
                LoadingView(text: "读取日志目录…")
            case .failed(let message) where tree.isEmpty:
                EmptyStateView(
                    symbol: "folder.badge.questionmark",
                    title: "无法读取日志目录",
                    message: message,
                    actionTitle: "重试"
                ) { Task { await load() } }
            default:
                if tree.isEmpty {
                    ScrollView {
                        EmptyStateView(
                            symbol: "tray",
                            title: "暂无日志",
                            message: "面板还没有产生任何日志文件，运行任务后即可在这里查看。"
                        )
                    }
                } else {
                    List {
                        Section {
                            ForEach(filtered) { item in
                                LogTreeRow(item: item)
                            }
                        } header: {
                            SectionHeader(
                                title: "日志目录",
                                subtitle: "共 \(tree.fileCountRecursive) 个日志文件"
                            )
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("日志")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $keyword, prompt: "搜索日志文件")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        if tree.isEmpty { state = .loading }
        do {
            tree = try await LogService.tree()
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            if apiError.isUnauthorized { session.handle(error); return }
            state = .failed(apiError.localizedDescription)
        }
    }
}

/// 目录 / 文件行。目录点击后进入本地渲染的子层级。
struct LogTreeRow: View {

    let item: QLFileItem

    @EnvironmentObject private var session: AppSession
    @State private var pendingDelete = false

    var body: some View {
        if item.isDirectory {
            NavigationLink {
                LogDirectoryView(directory: item)
                    .environmentObject(session)
            } label: {
                rowContent
            }
            .listRowBackground(Theme.surfaceElevated)
        } else {
            NavigationLink {
                LogConsoleView(
                    title: item.title,
                    subtitle: item.createTimeText
                ) { offset, limit, tail in
                    try await LogService.detail(
                        path: parentPath,
                        file: item.title,
                        offset: offset,
                        limit: limit,
                        tail: tail
                    )
                }
                .environmentObject(session)
            } label: {
                rowContent
            }
            .listRowBackground(Theme.surfaceElevated)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    pendingDelete = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
            .alert(isPresented: $pendingDelete) {
                Alert(
                    title: Text("删除日志"),
                    message: Text("确定删除「\(item.title)」吗？"),
                    primaryButton: .destructive(Text("删除")) {
                        Task {
                            do {
                                try await LogService.remove(path: parentPath, filename: item.title)
                                session.showToast("已删除日志文件", tone: .success)
                            } catch {
                                session.handle(error)
                            }
                        }
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
    }

    /// 父级相对路径（面板要求 path 与 file 分开传）
    private var parentPath: String {
        var value = item.parent ?? ""
        while value.hasPrefix("/") { value.removeFirst() }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    private var rowContent: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.text")
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
}

/// 子目录（不再请求网络，直接使用已拿到的树）
struct LogDirectoryView: View {

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
                    LogTreeRow(item: item)
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(directory.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
