//
//  MoreView.swift
//  QingLong
//
//  「更多」页：功能导航与账号操作。
//

import SwiftUI

struct MoreView: View {

    @EnvironmentObject private var session: AppSession

    @State private var showsServerList = false
    @State private var showsLogoutConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.large) {
                accountCard
                navigationGroups
                logoutButton
                footer
            }
            .padding(Theme.Spacing.large)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("更多")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showsServerList) {
            ServerListView(mode: .manage).environmentObject(session)
        }
        .alert(isPresented: $showsLogoutConfirm) {
            Alert(
                title: Text("退出登录"),
                message: Text("将清除本机保存的登录凭证，下次需要重新输入账号密码。"),
                primaryButton: .destructive(Text("退出")) { session.logout() },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    // MARK: - 账号卡片

    private var accountCard: some View {
        VStack(spacing: Theme.Spacing.medium) {
            HStack(spacing: Theme.Spacing.medium) {
                ZStack {
                    Circle()
                        .fill(Theme.brandGradient)
                        .frame(width: 48, height: 48)
                    Text(String((session.user?.username ?? "Q").prefix(1)).uppercased())
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.user?.username ?? "未知用户")
                        .font(Theme.Font.headline)
                        .foregroundColor(Theme.textPrimary)
                    Text(session.activeServer?.displayName ?? "未选择服务器")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                StatusPill(text: "已登录", tone: .success, symbol: "checkmark.seal.fill", compact: true)
            }

            Divider().background(Theme.separator)

            Button {
                showsServerList = true
            } label: {
                HStack(spacing: Theme.Spacing.small) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                    Text("切换 / 管理服务器")
                        .font(Theme.Font.callout.weight(.medium))
                    Spacer(minLength: 0)
                    Text(session.activeServer?.hostDescription ?? "")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.textTertiary)
                }
                .foregroundColor(Theme.brand)
            }
            .buttonStyle(.pressable)
        }
        .qlCard()
    }

    // MARK: - 导航分组

    private var navigationGroups: some View {
        VStack(spacing: Theme.Spacing.large) {
            navGroup(title: "内容管理") {
                navRow("订阅管理", "arrow.triangle.2.circlepath", .success) { SubscriptionListView() }
                navRow("脚本管理", "doc.text", .progress) { ScriptBrowserView() }
                navRow("日志浏览", "doc.text.magnifyingglass", .info) { LogBrowserView() }
                navRow("依赖管理", "cube.box.fill", .warning) { DependenceListView() }
            }

            navGroup(title: "面板配置") {
                navRow("配置文件", "slider.horizontal.3", .warning) { ConfigFilesView() }
                navRow("面板设置", "gearshape.fill", .progress) { SystemConfigView() }
                navRow("通知设置", "bell.badge.fill", .danger) { NotificationSettingsView() }
                navRow("账号与安全", "lock.shield.fill", .info) { AccountView() }
                navRow("开放接口", "link.circle.fill", .success) { OpenAppsView() }
            }

            navGroup(title: "运维工具") {
                navRow("命令调试", "terminal.fill", .progress) { CommandRunnerView() }
                navRow("数据备份", "externaldrive.fill", .warning) { DataBackupView() }
                navRow("面板系统日志", "doc.plaintext.fill", .info) { SystemLogView() }
            }

            navGroup(title: "关于") {
                navRow("关于\(AppInfo.displayName)", "info.circle.fill", .neutral) { AboutView() }
            }
        }
    }

    private func navGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader(title: title)
            VStack(spacing: 0) {
                content()
            }
            .qlCard(padding: Theme.Spacing.small)
        }
    }

    private func navRow<Destination: View>(
        _ title: String,
        _ symbol: String,
        _ tone: StatusTone,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            NavigationRow(symbol: symbol, title: title, subtitle: "", tone: tone)
                .background(Color.clear)
        }
        .buttonStyle(.pressable)
    }

    // MARK: - 退出

    private var logoutButton: some View {
        Button {
            showsLogoutConfirm = true
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("退出登录")
            }
            .font(Theme.Font.callout.weight(.semibold))
            .foregroundColor(Theme.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.medium)
            .background(Theme.danger.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.pressable)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("\(AppInfo.displayName) v\(AppInfo.versionDescription)")
            Text("第三方开源客户端 · 与青龙面板官方无隶属关系")
        }
        .font(Theme.Font.caption)
        .foregroundColor(Theme.textTertiary)
        .multilineTextAlignment(.center)
        .padding(.top, Theme.Spacing.small)
    }
}
