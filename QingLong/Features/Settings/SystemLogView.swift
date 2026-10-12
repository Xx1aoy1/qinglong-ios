//
//  SystemLogView.swift
//  QingLong
//
//  「面板系统日志」：查看面板自身运行日志。
//  对应接口：GET /api/system/log、DELETE /api/system/log
//

import SwiftUI
import UIKit

@MainActor
final class SystemLogViewModel: ObservableObject {

    enum TimeRange: String, CaseIterable, Identifiable {
        case today, threeDays, all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return "今天"
            case .threeDays: return "最近 3 天"
            case .all: return "全部"
            }
        }
    }

    @Published var range: TimeRange = .today
    @Published var text: String = ""
    @Published var state: LoadState = .idle
    @Published var isDeleting = false

    var isEmpty: Bool { text.trimmed.isEmpty }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(text.utf8.count), countStyle: .file)
    }

    func load() async {
        state = .loading
        do {
            let result = try await SystemService.systemLog(
                startTime: startTime,
                endTime: endTime,
                limit: 1024 * 1024
            )
            text = result
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            state = .failed(apiError.localizedDescription)
        }
    }

    func delete() async throws {
        isDeleting = true
        defer { isDeleting = false }
        try await SystemService.deleteSystemLog()
        text = ""
        state = .loaded
    }

    private var startTime: String? {
        switch range {
        case .today: return Self.dayFormatter.string(from: Date())
        case .threeDays: return Self.dayFormatter.string(from: Date().addingTimeInterval(-2 * 86_400))
        case .all: return "2000-01-01"
        }
    }

    private var endTime: String? {
        Self.dayFormatter.string(from: Date())
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

// MARK: - 页面

struct SystemLogView: View {

    @EnvironmentObject private var session: AppSession
    @StateObject private var model = SystemLogViewModel()

    @State private var showsDeleteConfirm = false
    @State private var showsShareSheet = false
    @State private var shareURL: URL?

    var body: some View {
        ZStack {
            Theme.surfaceSunken.ignoresSafeArea()

            VStack(spacing: 0) {
                rangeBar
                Divider().background(Theme.separator)
                console
            }

            if model.state.isLoading && model.text.isEmpty {
                LoadingView(text: "读取系统日志…")
            }

            if case .failed(let message) = model.state, model.text.isEmpty {
                EmptyStateView(
                    symbol: "doc.questionmark",
                    title: "无法读取系统日志",
                    message: message,
                    actionTitle: "重试"
                ) {
                    Task { await model.load() }
                }
            }
        }
        .navigationTitle("面板系统日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        Task { await model.load() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }

                    Button {
                        UIPasteboard.general.string = model.text
                        session.showToast("已复制系统日志", tone: .success)
                    } label: {
                        Label("复制全部", systemImage: "doc.on.doc")
                    }
                    .disabled(model.isEmpty)

                    Button {
                        exportLog()
                    } label: {
                        Label("分享 / 导出", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.isEmpty)

                    Divider()

                    Button(role: .destructive) {
                        showsDeleteConfirm = true
                    } label: {
                        Label("清空系统日志", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .onAppear {
            if model.text.isEmpty {
                Task { await model.load() }
            }
        }
        .sheet(isPresented: $showsShareSheet) {
            ShareSheet(items: [shareURL].compactMap { $0 })
        }
        .alert(isPresented: $showsDeleteConfirm) {
            Alert(
                title: Text("清空系统日志"),
                message: Text("将删除面板上的全部系统日志文件，该操作不可撤销。"),
                primaryButton: .destructive(Text("清空")) {
                    Task {
                        do {
                            try await model.delete()
                            session.showToast("已清空系统日志", tone: .success)
                        } catch {
                            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
                            if apiError.isUnauthorized {
                                session.handle(error)
                            } else {
                                session.showToast("清空失败：\(apiError.localizedDescription)", tone: .danger)
                            }
                        }
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    // MARK: - 范围切换

    private var rangeBar: some View {
        HStack(spacing: Theme.Spacing.small) {
            ForEach(SystemLogViewModel.TimeRange.allCases) { item in
                FilterChip(
                    title: item.title,
                    count: nil,
                    isSelected: model.range == item
                ) {
                    guard model.range != item else { return }
                    model.range = item
                    Task { await model.load() }
                }
            }

            Spacer(minLength: 0)

            if !model.isEmpty {
                Text(model.sizeText)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .padding(.horizontal, Theme.Spacing.large)
        .padding(.vertical, Theme.Spacing.small)
        .background(Theme.surface)
    }

    // MARK: - 控制台

    private var console: some View {
        ScrollView {
            Text(model.isEmpty ? "（所选时间段内暂无系统日志）" : model.text)
                .font(Theme.Font.monoSmall)
                .foregroundColor(model.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.medium)
        }
    }

    // MARK: - 导出

    private func exportLog() {
        let stamp = Int(Date().timeIntervalSince1970)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qinglong-system-\(stamp).log")
        do {
            try model.text.write(to: url, atomically: true, encoding: .utf8)
            shareURL = url
            showsShareSheet = true
        } catch {
            session.showToast("导出失败：\(error.localizedDescription)", tone: .danger)
        }
    }
}
