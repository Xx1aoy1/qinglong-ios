//
//  AccountView.swift
//  QingLong
//
//  账号与安全：修改账号密码、两步验证、登录日志、IP 黑名单。
//

import SwiftUI
import UIKit

@MainActor
final class AccountViewModel: ObservableObject {

    @Published var user: QLUser?
    @Published var loginLogs: [LoginLogItem] = []
    @Published var blacklist: [String] = []
    @Published var state: LoadState = .idle
    @Published var isWorking = false

    func load(session: AppSession) async {
        if user == nil { state = .loading }
        do {
            async let userTask = UserService.currentUser()
            async let logTask = UserService.loginLog()
            async let blacklistTask = UserService.ipBlacklist()
            user = try await userTask
            loginLogs = try await logTask
            blacklist = try await blacklistTask
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            if apiError.isUnauthorized { session.handle(error); return }
            state = .failed(apiError.localizedDescription)
        }
    }

    func refreshUserOnly() async {
        user = try? await UserService.currentUser()
    }
}

struct AccountView: View {

    @EnvironmentObject private var session: AppSession
    @StateObject private var viewModel = AccountViewModel()

    @State private var showsPasswordSheet = false
    @State private var newUsername = ""
    @State private var newPassword = ""
    @State private var newPasswordConfirm = ""

    @State private var showsTwoFactorSetup = false
    @State private var twoFactorSetup: TwoFactorSetup?
    @State private var twoFactorCode = ""
    @State private var showsTwoFactorDeactivate = false

    @State private var showsBlockIp = false
    @State private var ipDraft = ""

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading where viewModel.user == nil:
                LoadingView(text: "读取账号信息…")
            case .failed(let message) where viewModel.user == nil:
                ScrollView {
                    EmptyStateView(
                        symbol: "person.crop.circle.badge.exclamationmark",
                        title: "无法读取账号信息",
                        message: message,
                        actionTitle: "重试"
                    ) { Task { await viewModel.load(session: session) } }
                }
            default:
                content
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("账号与安全")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load(session: session) }
        .task { await viewModel.load(session: session) }
        .sheet(isPresented: $showsPasswordSheet) { passwordSheet }
        .sheet(isPresented: $showsTwoFactorSetup) { twoFactorSetupSheet }
        .sheet(isPresented: $showsBlockIp) {
            PromptSheet(
                title: "封禁 IP",
                message: "被封禁的 IP 将无法登录面板。",
                placeholder: "例如 1.2.3.4",
                text: $ipDraft,
                keyboardType: .numbersAndPunctuation
            ) {
                Task { await blockCurrentIp() }
            }
        }
        .alert(isPresented: $showsTwoFactorDeactivate) {
            Alert(
                title: Text("关闭两步验证"),
                message: Text("关闭后登录将不再需要验证码，安全性会降低。"),
                primaryButton: .destructive(Text("关闭")) {
                    Task {
                        await perform {
                            try await UserService.deactivateTwoFactor()
                            await viewModel.refreshUserOnly()
                            session.showToast("已关闭两步验证", tone: .info)
                        }
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .overlay { if viewModel.isWorking { BlockingOverlay(text: "处理中…") } }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.large) {
                profileCard
                securitySection
                loginLogSection
                blacklistSection
            }
            .padding(Theme.Spacing.large)
        }
    }

    // MARK: - 头像卡片

    private var profileCard: some View {
        HStack(spacing: Theme.Spacing.medium) {
            ZStack {
                Circle()
                    .fill(Theme.brandGradient)
                    .frame(width: 54, height: 54)
                Text(String((viewModel.user?.username ?? "Q").prefix(1)).uppercased())
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.user?.username ?? "—")
                    .font(Theme.Font.headline)
                    .foregroundColor(Theme.textPrimary)
                Text(session.activeServer?.hostDescription ?? "—")
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .qlCard()
    }

    // MARK: - 安全

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader(title: "安全")

            VStack(spacing: 0) {
                Button {
                    newUsername = viewModel.user?.username ?? ""
                    newPassword = ""
                    newPasswordConfirm = ""
                    showsPasswordSheet = true
                } label: {
                    NavigationRow(
                        symbol: "key.fill",
                        title: "修改用户名 / 密码",
                        subtitle: "修改后所有已登录设备都会失效",
                        tone: .info
                    )
                }
                .buttonStyle(.pressable)

                Divider().background(Theme.separator).padding(.leading, 44)

                Button {
                    if viewModel.user?.twoFactorActivated == true {
                        showsTwoFactorDeactivate = true
                    } else {
                        Task { await startTwoFactorSetup() }
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.medium) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.brand)
                            .frame(width: 32, height: 32)
                            .background(Theme.brand.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("两步验证")
                                .font(Theme.Font.callout.weight(.medium))
                                .foregroundColor(Theme.textPrimary)
                            Text("使用身份验证器 App 生成动态验证码")
                                .font(Theme.Font.caption)
                                .foregroundColor(Theme.textTertiary)
                        }

                        Spacer(minLength: 0)

                        StatusPill(
                            text: viewModel.user?.twoFactorActivated == true ? "已开启" : "未开启",
                            tone: viewModel.user?.twoFactorActivated == true ? .success : .neutral,
                            compact: true
                        )
                    }
                    .padding(Theme.Spacing.medium)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 0.6)
                    )
                }
                .buttonStyle(.pressable)
            }
        }
    }

    // MARK: - 登录日志

    private var loginLogSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader(title: "登录日志", subtitle: "最近 \(min(viewModel.loginLogs.count, 20)) 条")

            if viewModel.loginLogs.isEmpty {
                Text("暂无登录记录")
                    .font(Theme.Font.callout)
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Theme.Spacing.large)
                    .qlCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.loginLogs.prefix(20).enumerated()), id: \.offset) { index, log in
                        HStack(spacing: Theme.Spacing.medium) {
                            Image(systemName: log.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(log.isSuccess ? Theme.success : Theme.danger)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(log.info?.address?.isEmpty == false ? log.info!.address! : (log.info?.ip ?? "—"))
                                    .font(Theme.Font.callout)
                                    .foregroundColor(Theme.textPrimary)
                                    .lineLimit(1)
                                Text("\(log.info?.platform ?? "—") · \(timestampText(log.info?.timestamp))")
                                    .font(Theme.Font.caption)
                                    .foregroundColor(Theme.textTertiary)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)

                        if index < min(viewModel.loginLogs.count, 20) - 1 {
                            Divider().background(Theme.separator)
                        }
                    }
                }
                .qlCard(padding: Theme.Spacing.medium)
            }
        }
    }

    private func timestampText(_ value: Int?) -> String {
        guard let value else { return "—" }
        return Date(timeIntervalSince1970: TimeInterval(value)).absoluteDescription
    }

    // MARK: - IP 黑名单

    private var blacklistSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                SectionHeader(title: "IP 黑名单", subtitle: "被封禁的 IP 无法登录面板")
                Spacer()
                Button {
                    ipDraft = ""
                    showsBlockIp = true
                } label: {
                    Label("添加", systemImage: "plus")
                        .font(Theme.Font.caption.weight(.semibold))
                        .foregroundColor(Theme.brand)
                }
            }

            if viewModel.blacklist.isEmpty {
                Text("暂无封禁记录")
                    .font(Theme.Font.callout)
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Theme.Spacing.large)
                    .qlCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.blacklist.enumerated()), id: \.offset) { index, ip in
                        HStack {
                            Image(systemName: "hand.raised.slash.fill")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.danger)
                            Text(ip)
                                .font(Theme.Font.mono)
                                .foregroundColor(Theme.textPrimary)
                            Spacer(minLength: 0)
                            Button("解除") {
                                Task { await unblock(ip) }
                            }
                            .font(Theme.Font.caption.weight(.semibold))
                            .foregroundColor(Theme.brand)
                        }
                        .padding(.vertical, 8)

                        if index < viewModel.blacklist.count - 1 {
                            Divider().background(Theme.separator)
                        }
                    }
                }
                .qlCard(padding: Theme.Spacing.medium)
            }
        }
    }

    // MARK: - 弹窗

    private var passwordSheet: some View {
        NavigationView {
            Form {
                Section {
                    TextField("用户名", text: $newUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    SecureField("新密码", text: $newPassword)
                    SecureField("确认新密码", text: $newPasswordConfirm)
                } header: {
                    SectionHeader(title: "修改账号", subtitle: "密码不能设置为 admin")
                } footer: {
                    if !newPasswordConfirm.isEmpty && newPassword != newPasswordConfirm {
                        Text("两次输入的密码不一致").foregroundColor(Theme.danger)
                    } else {
                        Text("修改成功后需要在所有设备上重新登录。")
                    }
                }
            }
            .navigationTitle("修改账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { showsPasswordSheet = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        let username = newUsername.trimmed
                        let password = newPassword
                        showsPasswordSheet = false
                        Task {
                            await perform {
                                _ = try await UserService.updateAccount(username: username, password: password)
                                await viewModel.refreshUserOnly()
                                session.showToast("账号已更新，请重新登录", tone: .success)
                                session.logout()
                            }
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .disabled(newUsername.trimmed.isEmpty || newPassword.count < 5 || newPassword != newPasswordConfirm)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var twoFactorSetupSheet: some View {
        NavigationView {
            Form {
                Section {
                    if let secret = twoFactorSetup?.secret {
                        InfoRow(label: "密钥", value: secret, mono: true, copyable: true)
                        Button {
                            UIPasteboard.general.string = secret
                            session.showToast("已复制密钥", tone: .success)
                        } label: {
                            Label("复制密钥", systemImage: "doc.on.doc")
                        }
                    }
                    if let url = twoFactorSetup?.url, !url.isEmpty {
                        Button {
                            UIPasteboard.general.string = url
                            session.showToast("已复制 otpauth 链接", tone: .success)
                        } label: {
                            Label("复制 otpauth 链接", systemImage: "link")
                        }
                    }
                } header: {
                    SectionHeader(title: "第一步：添加密钥", subtitle: "在身份验证器 App 中手动添加，或粘贴 otpauth 链接")
                }

                Section {
                    TextField("6 位验证码", text: $twoFactorCode)
                        .keyboardType(.numberPad)
                        .font(Theme.Font.mono)
                } header: {
                    SectionHeader(title: "第二步：验证")
                }

                Section {
                    Button {
                        let code = twoFactorCode.trimmed
                        showsTwoFactorSetup = false
                        Task {
                            await perform {
                                try await UserService.activateTwoFactor(code: code)
                                await viewModel.refreshUserOnly()
                                session.showToast("两步验证已开启", tone: .success)
                            }
                        }
                    } label: {
                        Text("开启两步验证").foregroundColor(Theme.brand)
                    }
                    .disabled(twoFactorCode.trimmed.count < 6)
                }
            }
            .navigationTitle("开启两步验证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { showsTwoFactorSetup = false }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 动作

    private func startTwoFactorSetup() async {
        await perform {
            twoFactorSetup = try await UserService.twoFactorSetup()
            twoFactorCode = ""
            showsTwoFactorSetup = true
        }
    }

    private func blockCurrentIp() async {
        let ip = ipDraft.trimmed
        guard !ip.isEmpty else { return }
        await perform {
            viewModel.blacklist = try await UserService.blockIp(ip)
            session.showToast("已封禁 \(ip)", tone: .success)
        }
    }

    private func unblock(_ ip: String) async {
        await perform {
            viewModel.blacklist = try await UserService.unblockIp(ip)
            session.showToast("已解除 \(ip)", tone: .info)
        }
    }

    private func perform(_ action: @escaping () async throws -> Void) async {
        viewModel.isWorking = true
        defer { viewModel.isWorking = false }
        do {
            try await action()
        } catch {
            session.handle(error)
        }
    }
}
