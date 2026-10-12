//
//  ServerListView.swift
//  QingLong
//
//  服务器（面板）列表。首次启动时作为引导页，运行中可作为「服务器管理」页打开。
//

import SwiftUI

struct ServerListView: View {

    enum Mode: Equatable {
        /// 首次启动引导
        case onboarding
        /// 已登录后从设置进入
        case manage
    }

    var mode: Mode = .onboarding

    @EnvironmentObject private var session: AppSession
    @Environment(\.presentationMode) private var presentationMode

    @State private var editing: ServerEditTarget?
    @State private var pendingDelete: ServerConfig?

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()

                if session.servers.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle(mode == .onboarding ? "连接青龙面板" : "服务器管理")
            .navigationBarTitleDisplayMode(mode == .onboarding ? .large : .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editing = .create
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }

                if mode == .manage {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("完成") { presentationMode.wrappedValue.dismiss() }
                    }
                }
            }
            .sheet(item: $editing) { target in
                ServerEditView(target: target)
                    .environmentObject(session)
            }
            .alert(item: $pendingDelete) { server in
                Alert(
                    title: Text("删除服务器"),
                    message: Text("将同时清除「\(server.displayName)」在本机保存的登录凭证。"),
                    primaryButton: .destructive(Text("删除")) {
                        withAnimation { session.deleteServer(server) }
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 子视图

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.medium) {
                ForEach(session.servers) { server in
                    Button {
                        select(server)
                    } label: {
                        ServerRow(
                            server: server,
                            isActive: session.activeServer?.id == server.id && mode == .manage
                        )
                    }
                    .buttonStyle(.pressable)
                    .contextMenu {
                        Button {
                            editing = .edit(server)
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            pendingDelete = server
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(Theme.Spacing.large)

            if mode == .onboarding {
                Text("提示：面板地址需从手机可访问，例如 http://192.168.1.10:5700")
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xlarge)
                    .padding(.top, Theme.Spacing.small)
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xlarge) {
                BrandLogo(size: 76)
                    .padding(.top, 40)

                VStack(spacing: Theme.Spacing.small) {
                    Text("欢迎使用\(AppInfo.displayName)")
                        .font(Theme.Font.title)
                        .foregroundColor(Theme.textPrimary)
                    Text("添加你的青龙面板地址即可开始管理定时任务、环境变量、日志与订阅。")
                        .font(Theme.Font.callout)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.xlarge)
                }

                Button {
                    editing = .create
                } label: {
                    Label("添加面板地址", systemImage: "plus.circle.fill")
                        .qlPrimaryButton()
                }
                .buttonStyle(.pressable)
                .padding(.horizontal, Theme.Spacing.xlarge)

                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    BulletLine("支持 http / https，端口默认 5700")
                    BulletLine("可添加多个面板，随时切换")
                    BulletLine("Token 保存在系统钥匙串中")
                }
                .padding(Theme.Spacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .qlCard(padding: 0)
                .padding(.horizontal, Theme.Spacing.xlarge)
            }
            .padding(.bottom, 40)
        }
    }

    private func select(_ server: ServerConfig) {
        session.switchTo(server: server)
        if mode == .manage {
            presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - 行

struct ServerRow: View {
    let server: ServerConfig
    var isActive: Bool = false

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isActive ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.brandSoft))
                    .frame(width: 44, height: 44)
                Image(systemName: "server.rack")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isActive ? .white : Theme.brand)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(server.displayName)
                        .font(Theme.Font.headline)
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    if isActive {
                        StatusPill(text: "当前", tone: .progress, symbol: "checkmark.circle.fill", compact: true)
                    }
                }

                Text(server.hostDescription)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)

                if let username = server.username, !username.isEmpty {
                    Text("账号 \(username)")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.textTertiary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(Theme.Spacing.medium)
        .qlCard(padding: 0)
    }
}

// MARK: - 编辑目标

enum ServerEditTarget: Identifiable {
    case create
    case edit(ServerConfig)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let server): return server.id.uuidString
        }
    }
}
