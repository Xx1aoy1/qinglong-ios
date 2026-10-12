//
//  LogConsoleView.swift
//  QingLong
//
//  通用日志控制台：支持增量跟随、暂停、复制、分享。
//  定时任务日志、订阅日志、面板日志共用此视图。
//

import SwiftUI
import UIKit

struct LogConsoleView: View {

    /// 拉取一个分片。offset 为 nil 表示从头（或末尾，取决于 tail）开始。
    typealias Fetch = (_ offset: Int?, _ limit: Int?, _ tail: Bool?) async throws -> LogChunk

    let title: String
    var subtitle: String?
    var fetch: Fetch
    /// 打开时是否自动跟随最新内容
    var autoFollow: Bool = true
    /// 轮询间隔（秒）
    var pollInterval: TimeInterval = 3

    @EnvironmentObject private var session: AppSession

    @State private var text: String = ""
    @State private var nextOffset: Int = 0
    @State private var total: Int = 0
    @State private var isFollowing = true
    @State private var isRunning = false
    @State private var state: LoadState = .idle
    @State private var pollTask: Task<Void, Never>?
    @State private var showsShareSheet = false

    private let chunkSize = 128 * 1024

    var body: some View {
        ZStack {
            Theme.surfaceSunken.ignoresSafeArea()

            VStack(spacing: 0) {
                statusBar
                Divider().background(Theme.separator)
                console
            }

            if state.isLoading && text.isEmpty {
                LoadingView(text: "读取日志…")
            }

            if case .failed(let message) = state, text.isEmpty {
                EmptyStateView(
                    symbol: "doc.questionmark",
                    title: "无法读取日志",
                    message: message,
                    actionTitle: "重试"
                ) {
                    Task { await reload() }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = text
                        session.showToast("已复制全部日志", tone: .success)
                    } label: {
                        Label("复制全部", systemImage: "doc.on.doc")
                    }

                    Button {
                        showsShareSheet = true
                    } label: {
                        Label("分享 / 导出", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button {
                        Task { await reload() }
                    } label: {
                        Label("重新加载", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .sheet(isPresented: $showsShareSheet) {
            ShareSheet(items: [exportFileURL()].compactMap { $0 })
        }
        .onAppear {
            isFollowing = autoFollow
            start()
        }
        .onDisappear { stop() }
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        HStack(spacing: Theme.Spacing.medium) {
            HStack(spacing: 5) {
                Circle()
                    .fill(isRunning ? Theme.brand : Theme.textTertiary)
                    .frame(width: 7, height: 7)
                Text(isRunning ? "运行中" : "已停止")
                    .font(Theme.Font.caption.weight(.medium))
                    .foregroundColor(Theme.textSecondary)
            }

            if let subtitle {
                Text(subtitle)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if total > 0 {
                Text(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textTertiary)
            }

            Button {
                isFollowing.toggle()
                if isFollowing { start() } else { stop() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isFollowing ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(isFollowing ? "暂停跟随" : "继续跟随")
                        .font(Theme.Font.caption.weight(.semibold))
                }
                .foregroundColor(isFollowing ? Theme.warning : Theme.brand)
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, Theme.Spacing.large)
        .padding(.vertical, Theme.Spacing.small)
        .background(Theme.surface)
    }

    // MARK: - 控制台

    private var console: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? "（暂无日志内容）" : text)
                    .font(Theme.Font.monoSmall)
                    .foregroundColor(Theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.medium)
                    .id("log-bottom")
            }
            .onChange(of: text.count) { _ in
                guard isFollowing, !text.isEmpty else { return }
                withAnimation(.linear(duration: 0.12)) {
                    proxy.scrollTo("log-bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - 拉取

    private func start() {
        stop()
        pollTask = Task { @MainActor in
            await reload()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                if Task.isCancelled { break }
                guard isFollowing else { continue }
                await fetchIncrement()
            }
        }
    }

    private func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func reload() async {
        state = .loading
        do {
            let chunk = try await fetch(nil, chunkSize, true)
            text = chunk.content
            nextOffset = chunk.nextOffset ?? chunk.content.utf8.count
            total = chunk.total ?? 0
            isRunning = chunk.isRunning || chunk.logStatus == "running"
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            state = .failed(apiError.localizedDescription)
            if apiError.isUnauthorized { session.handle(error) }
        }
    }

    private func fetchIncrement() async {
        do {
            let chunk = try await fetch(nextOffset, chunkSize, false)
            isRunning = chunk.isRunning || chunk.logStatus == "running"

            if chunk.truncated == true {
                // 日志被轮转或截断，重置
                text = chunk.content
                nextOffset = chunk.nextOffset ?? chunk.content.utf8.count
                total = chunk.total ?? 0
                return
            }

            let appended = chunk.content
            if !appended.isEmpty {
                text += appended
                if text.utf8.count > 2 * 1024 * 1024 {
                    // 控制内存占用：保留末尾 1MB
                    let data = Data(text.utf8.suffix(1024 * 1024))
                    text = String(data: data, encoding: .utf8) ?? String(text.suffix(400_000))
                }
            }
            nextOffset = chunk.nextOffset ?? (nextOffset + appended.utf8.count)
            total = chunk.total ?? total
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled || apiError.isRetryable { return }
            if apiError.isUnauthorized { session.handle(error) }
        }
    }

    // MARK: - 导出

    private func exportFileURL() -> URL? {
        guard !text.isEmpty else { return nil }
        let safeTitle = title.replacingOccurrences(of: "/", with: "_")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeTitle)-\(Int(Date().timeIntervalSince1970)).log")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - 分享面板

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
