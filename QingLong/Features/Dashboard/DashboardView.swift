//
//  DashboardView.swift
//  QingLong
//
//  概览页：面板状态、关键指标、最近运行。
//

import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {

    @Published private(set) var crons: [QLCron] = []
    @Published private(set) var envCount: Int = 0
    @Published private(set) var subscriptionCount: Int = 0
    @Published private(set) var dependenceBusy: Int = 0
    @Published private(set) var config: SystemConfig?
    @Published var state: LoadState = .idle

    var runningCrons: [QLCron] { crons.filter { $0.statusValue == .running } }
    var disabledCrons: [QLCron] { crons.filter { $0.statusValue == .disabled } }
    var enabledCrons: [QLCron] { crons.filter { $0.statusValue != .disabled } }

    var recentCrons: [QLCron] {
        crons
            .filter { ($0.last_running_time ?? 0) > 0 }
            .sorted { ($0.last_running_time ?? 0) > ($1.last_running_time ?? 0) }
            .prefix(6)
            .map { $0 }
    }

    func load(session: AppSession) async {
        if state == .idle { state = .loading }
        do {
            async let cronsTask = CronService.list()
            async let envsTask = EnvService.list()
            async let subsTask = SubscriptionService.list()
            async let depsTask = DependenceService.list()
            async let configTask = SystemService.config()

            let (c, e, s, d, cfg) = try await (cronsTask, envsTask, subsTask, depsTask, configTask)
            crons = c
            envCount = e.count
            subscriptionCount = s.count
            dependenceBusy = d.busyCount
            config = cfg
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            if apiError.isUnauthorized {
                session.handle(error)
                return
            }
            state = .failed(apiError.localizedDescription)
        }
    }
}

struct DashboardView: View {

    @EnvironmentObject private var session: AppSession
    @StateObject private var viewModel = DashboardViewModel()
    @State private var showsCommandRunner = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.large) {
                panelCard
                metricsGrid
                quickActions
                recentSection
            }
            .padding(Theme.Spacing.large)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("概览")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        }
        .refreshable { await refresh() }
        .task { await viewModel.load(session: session) }
        .sheet(isPresented: $showsCommandRunner) {
            CommandRunnerView().environmentObject(session)
        }
    }

    // MARK: - 面板卡片

    private var panelCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(alignment: .top, spacing: Theme.Spacing.medium) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.brandGradient)
                        .frame(width: 46, height: 46)
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(panelTitle)
                        .font(Theme.Font.headline)
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)

                    Text(session.activeServer?.hostDescription ?? "—")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                StatusPill(
                    text: viewModel.state.errorText == nil ? "在线" : "异常",
                    tone: viewModel.state.errorText == nil ? .success : .danger,
                    symbol: viewModel.state.errorText == nil ? "wifi" : "wifi.slash"
                )
            }

            Divider().background(Theme.separator)

            HStack(spacing: Theme.Spacing.large) {
                miniStat(
                    title: "版本",
                    value: session.systemStatus?.version ?? "—"
                )
                miniStat(
                    title: "分支",
                    value: session.systemStatus?.branch ?? "—"
                )
                miniStat(
                    title: "账号",
                    value: session.user?.username ?? "—"
                )
            }

            if let error = viewModel.state.errorText {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.danger)
            }
        }
        .qlCard()
    }

    private var panelTitle: String {
        if let title = viewModel.config?.info?.panelTitle, !title.isEmpty {
            return title
        }
        return session.activeServer?.displayName ?? AppInfo.displayName
    }

    private func miniStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundColor(Theme.textTertiary)
            Text(value)
                .font(Theme.Font.callout.weight(.medium))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 指标

    private var metricsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Theme.Spacing.medium),
                      GridItem(.flexible(), spacing: Theme.Spacing.medium)],
            spacing: Theme.Spacing.medium
        ) {
            MetricCard(
                title: "定时任务",
                value: "\(viewModel.crons.count)",
                subtitle: "运行中 \(viewModel.runningCrons.count) · 禁用 \(viewModel.disabledCrons.count)",
                symbol: "clock.fill",
                tone: .success
            )
            MetricCard(
                title: "环境变量",
                value: "\(viewModel.envCount)",
                subtitle: "点击底部「变量」管理",
                symbol: "shippingbox.fill",
                tone: .info
            )
            MetricCard(
                title: "订阅",
                value: "\(viewModel.subscriptionCount)",
                subtitle: "自动拉取脚本仓库",
                symbol: "arrow.triangle.2.circlepath",
                tone: .progress
            )
            MetricCard(
                title: "依赖任务",
                value: "\(viewModel.dependenceBusy)",
                subtitle: viewModel.dependenceBusy > 0 ? "有任务正在执行" : "当前无进行中任务",
                symbol: "cube.box.fill",
                tone: viewModel.dependenceBusy > 0 ? .warning : .neutral
            )
        }
    }

    // MARK: - 快捷操作

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(title: "快捷操作")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Theme.Spacing.medium),
                          GridItem(.flexible(), spacing: Theme.Spacing.medium)],
                spacing: Theme.Spacing.medium
            ) {
                QuickAction(title: "命令调试", symbol: "terminal.fill", tone: .progress) {
                    showsCommandRunner = true
                }
                NavigationLink {
                    LogBrowserView()
                } label: {
                    QuickActionLabel(title: "日志浏览", symbol: "doc.text.magnifyingglass", tone: .info)
                }
                .buttonStyle(.pressable)

                NavigationLink {
                    SubscriptionListView()
                } label: {
                    QuickActionLabel(title: "订阅管理", symbol: "arrow.triangle.2.circlepath", tone: .success)
                }
                .buttonStyle(.pressable)

                NavigationLink {
                    DependenceListView()
                } label: {
                    QuickActionLabel(title: "依赖管理", symbol: "cube.box.fill", tone: .warning)
                }
                .buttonStyle(.pressable)

                NavigationLink {
                    ConfigFilesView()
                } label: {
                    QuickActionLabel(title: "配置文件", symbol: "slider.horizontal.3", tone: .neutral)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    // MARK: - 最近运行

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack {
                SectionHeader(title: "最近运行")
                Spacer()
                NavigationLink("全部", destination: CronListView())
                    .font(Theme.Font.caption.weight(.semibold))
            }

            if viewModel.recentCrons.isEmpty {
                Text("暂无运行记录")
                    .font(Theme.Font.callout)
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Theme.Spacing.xlarge)
                    .qlCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.recentCrons.enumerated()), id: \.element.id) { index, cron in
                        NavigationLink {
                            CronDetailView(cronID: cron.id)
                        } label: {
                            RecentCronRow(cron: cron)
                        }
                        .buttonStyle(.pressable)

                        if index < viewModel.recentCrons.count - 1 {
                            Divider().background(Theme.separator).padding(.leading, 44)
                        }
                    }
                }
                .qlCard(padding: Theme.Spacing.small)
            }
        }
    }

    private func refresh() async {
        await session.refreshSystemStatus()
        await viewModel.load(session: session)
    }
}

// MARK: - 子组件

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let tone: StatusTone

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tone.color)
                Spacer()
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
            }

            Text(title)
                .font(Theme.Font.callout.weight(.medium))
                .foregroundColor(Theme.textPrimary)

            Text(subtitle)
                .font(Theme.Font.caption)
                .foregroundColor(Theme.textTertiary)
                .lineLimit(2)
                .frame(minHeight: 30, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .qlCard(padding: Theme.Spacing.medium)
    }
}

private struct QuickAction: View {
    let title: String
    let symbol: String
    let tone: StatusTone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            QuickActionLabel(title: title, symbol: symbol, tone: tone)
        }
        .buttonStyle(.pressable)
    }
}

private struct QuickActionLabel: View {
    let title: String
    let symbol: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tone.color)
                .frame(width: 30, height: 30)
                .background(tone.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text(title)
                .font(Theme.Font.callout.weight(.medium))
                .foregroundColor(Theme.textPrimary)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(Theme.Spacing.medium)
        .frame(maxWidth: .infinity)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 0.6)
        )
    }
}

private struct RecentCronRow: View {
    let cron: QLCron

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Image(systemName: cron.statusValue.symbol)
                .font(.system(size: 16))
                .foregroundColor(cron.statusValue.tone.color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(cron.title)
                    .font(Theme.Font.callout.weight(.medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text(cron.lastRunText)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textTertiary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(.vertical, Theme.Spacing.small)
        .padding(.horizontal, Theme.Spacing.small)
        .contentShape(Rectangle())
    }
}
