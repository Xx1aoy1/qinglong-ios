//
//  LoginView.swift
//  QingLong
//
//  登录页：账号密码登录、两步验证、面板初始化引导。
//

import SwiftUI

struct LoginView: View {

    @EnvironmentObject private var session: AppSession

    @State private var username: String = "admin"
    @State private var password: String = ""
    @State private var twoFactorCode: String = ""
    @State private var rememberPassword: Bool = false

    @State private var isSubmitting = false
    @State private var showTwoFactor = false
    @State private var errorText: String?
    @State private var showServerList = false
    @State private var showInitialize = false

    @State private var initUsername = "admin"
    @State private var initPassword = ""
    @State private var initPasswordConfirm = ""

    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case username, password, code
    }

    private var server: ServerConfig? { session.activeServer }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.Spacing.large) {
                    header
                    credentialCard

                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Font.callout)
                            .foregroundColor(Theme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Spacing.medium)
                            .background(Theme.danger.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: Theme.Spacing.small) {
                            if isSubmitting {
                                ProgressView().tint(.white).scaleEffect(0.85)
                            }
                            Text(isSubmitting ? "登录中…" : "登录")
                        }
                        .qlPrimaryButton(enabled: canSubmit)
                    }
                    .buttonStyle(.pressable)
                    .disabled(!canSubmit)

                    if session.systemStatus?.isInitialized == false {
                        initializeHint
                    }

                    footer
                }
                .padding(Theme.Spacing.large)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $showServerList) {
                ServerListView(mode: .manage).environmentObject(session)
            }
            .sheet(isPresented: $showTwoFactor) {
                twoFactorSheet
            }
            .sheet(isPresented: $showInitialize) {
                initializeSheet
            }
            .onAppear(perform: prefill)
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 头部

    private var header: some View {
        VStack(spacing: Theme.Spacing.medium) {
            BrandLogo(size: 72)
                .padding(.top, Theme.Spacing.large)

            VStack(spacing: 4) {
                Text(AppInfo.displayName)
                    .font(Theme.Font.title)
                    .foregroundColor(Theme.textPrimary)
                Text("登录后即可管理你的青龙面板")
                    .font(Theme.Font.callout)
                    .foregroundColor(Theme.textSecondary)
            }

            Button {
                showServerList = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 12, weight: .semibold))
                    Text(server?.displayName ?? "选择服务器")
                        .font(Theme.Font.caption.weight(.medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(Theme.brand)
                .padding(.horizontal, Theme.Spacing.medium)
                .padding(.vertical, 7)
                .background(Theme.brandSoft)
                .clipShape(Capsule())
            }
            .buttonStyle(.pressable)

            if let host = server?.hostDescription {
                Text(host)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - 表单

    private var credentialCard: some View {
        VStack(spacing: Theme.Spacing.medium) {
            LabeledField(symbol: "person.fill", title: "用户名") {
                TextField("admin", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focused, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
            }

            Divider().background(Theme.separator)

            LabeledField(symbol: "lock.fill", title: "密码") {
                SecureField("请输入密码", text: $password)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }
            }

            Divider().background(Theme.separator)

            Toggle(isOn: $rememberPassword) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("记住密码")
                        .font(Theme.Font.callout)
                        .foregroundColor(Theme.textPrimary)
                    Text("保存在系统钥匙串，便于 Token 过期后自动重登")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.textTertiary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.brand))
            .onChange(of: rememberPassword) { value in
                session.rememberPassword = value
            }
        }
        .qlCard()
    }

    private var initializeHint: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Label("面板尚未初始化", systemImage: "exclamationmark.circle.fill")
                .font(Theme.Font.headline)
                .foregroundColor(Theme.warning)

            Text("检测到该面板仍使用默认账号（admin / admin），请先设置你自己的管理员账号密码。")
                .font(Theme.Font.callout)
                .foregroundColor(Theme.textSecondary)

            Button("立即初始化") { showInitialize = true }
                .font(Theme.Font.callout.weight(.semibold))
                .foregroundColor(Theme.brand)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .qlCard()
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("客户端为第三方开源项目，通过面板公开 HTTP 接口通信")
                .font(Theme.Font.caption)
                .foregroundColor(Theme.textTertiary)
            Text("v\(AppInfo.versionDescription)")
                .font(Theme.Font.caption)
                .foregroundColor(Theme.textTertiary)
        }
        .padding(.top, Theme.Spacing.small)
    }

    // MARK: - 两步验证

    private var twoFactorSheet: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.Spacing.large) {
                    VStack(spacing: Theme.Spacing.small) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 38))
                            .foregroundColor(Theme.brand)
                        Text("两步验证")
                            .font(Theme.Font.title)
                            .foregroundColor(Theme.textPrimary)
                        Text("请输入身份验证器 App 中当前显示的 6 位验证码")
                            .font(Theme.Font.callout)
                            .foregroundColor(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, Theme.Spacing.xlarge)

                    TextField("000000", text: $twoFactorCode)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                        .focused($focused, equals: .code)
                        .padding(.vertical, Theme.Spacing.medium)
                        .qlCard(padding: Theme.Spacing.medium)

                    Button {
                        Task { await submitTwoFactor() }
                    } label: {
                        Text(isSubmitting ? "校验中…" : "验证并登录")
                            .qlPrimaryButton(enabled: twoFactorCode.count >= 6 && !isSubmitting)
                    }
                    .buttonStyle(.pressable)
                    .disabled(twoFactorCode.count < 6 || isSubmitting)
                }
                .padding(Theme.Spacing.large)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("验证身份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("返回") { showTwoFactor = false }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 初始化面板

    private var initializeSheet: some View {
        NavigationView {
            Form {
                Section {
                    TextField("管理员用户名", text: $initUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    SecureField("设置密码", text: $initPassword)
                    SecureField("确认密码", text: $initPasswordConfirm)
                } header: {
                    SectionHeader(title: "设置管理员账号", subtitle: "密码不能设置为 admin")
                }

                Section {
                    Button {
                        Task { await doInitialize() }
                    } label: {
                        HStack {
                            Spacer()
                            Text(isSubmitting ? "提交中…" : "完成初始化")
                            Spacer()
                        }
                    }
                    .disabled(!canInitialize || isSubmitting)
                } footer: {
                    if initPassword != initPasswordConfirm && !initPasswordConfirm.isEmpty {
                        Text("两次输入的密码不一致")
                            .foregroundColor(Theme.danger)
                    }
                }
            }
            .navigationTitle("初始化面板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { showInitialize = false }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 逻辑

    private var canSubmit: Bool {
        !isSubmitting && !username.trimmed.isEmpty && !password.isEmpty
    }

    private var canInitialize: Bool {
        !initUsername.trimmed.isEmpty
            && initPassword.count >= 5
            && initPassword == initPasswordConfirm
    }

    private func prefill() {
        rememberPassword = session.rememberPassword
        if let saved = server?.username, !saved.isEmpty {
            username = saved
        }
        if let server, let savedPassword = session.savedPassword(for: server) {
            password = savedPassword
        }

        // 顺带探测面板状态（是否需要初始化）
        Task { await refreshStatus() }
    }

    private func refreshStatus() async {
        await session.refreshSystemStatus()
    }

    private func submit() async {
        guard canSubmit else { return }
        focused = nil
        isSubmitting = true
        errorText = nil
        defer { isSubmitting = false }

        do {
            let outcome = try await session.login(username: username.trimmed, password: password)
            if outcome == .needsTwoFactor {
                twoFactorCode = ""
                showTwoFactor = true
                focused = .code
            }
        } catch {
            errorText = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    private func submitTwoFactor() async {
        isSubmitting = true
        errorText = nil
        defer { isSubmitting = false }
        do {
            try await session.verifyTwoFactor(
                username: username.trimmed,
                password: password,
                code: twoFactorCode.trimmed
            )
            showTwoFactor = false
        } catch {
            let text = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            errorText = text
            session.showToast(text, tone: .danger)
        }
    }

    private func doInitialize() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await session.initialize(username: initUsername.trimmed, password: initPassword)
            showInitialize = false
            username = initUsername.trimmed
            password = initPassword
            await submit()
        } catch {
            session.showToast(
                (error as? APIError)?.localizedDescription ?? error.localizedDescription,
                tone: .danger
            )
        }
    }
}

// MARK: - 带图标的输入行

struct LabeledField<Content: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textTertiary)
                .frame(width: 20)

            Text(title)
                .font(Theme.Font.callout)
                .foregroundColor(Theme.textSecondary)
                .frame(width: 54, alignment: .leading)

            content()
                .font(Theme.Font.body)
                .foregroundColor(Theme.textPrimary)
        }
    }
}
