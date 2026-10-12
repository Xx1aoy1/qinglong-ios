//
//  NotificationSettingsView.swift
//  QingLong
//
//  通知设置。面板在保存时会立即发送一条测试通知，失败返回 code 400，
//  因此本页的「保存」等价于「保存并测试」。
//

import SwiftUI

@MainActor
final class NotificationViewModel: ObservableObject {

    @Published var values: [String: JSONValue] = [:]
    @Published var state: LoadState = .idle
    @Published var isSaving = false
    @Published var showsChannelPicker = false

    var channelType: String {
        let current = values.string("type")
        return current.isEmpty ? "bark" : current
    }

    var channel: NotificationChannel {
        NotificationCatalog.channel(for: channelType) ?? NotificationCatalog.channels[0]
    }

    func binding(for key: String) -> Binding<String> {
        Binding(
            get: { self.values.string(key) },
            set: { self.values.setString(key, $0) }
        )
    }

    func load(session: AppSession) async {
        if values.isEmpty { state = .loading }
        do {
            let settings = try await UserService.notificationSettings()
            values = settings.values
            if settings.type.isEmpty {
                values["type"] = .string("bark")
            } else {
                values["type"] = .string(settings.type)
            }
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            if apiError.isUnauthorized { session.handle(error); return }
            state = .failed(apiError.localizedDescription)
        }
    }

    func select(_ type: String) {
        values["type"] = .string(type)
    }

    func save(session: AppSession) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let settings = NotificationSettings(type: channelType, values: values)
            try await UserService.saveNotificationSettings(settings)
            session.showToast("已保存，测试通知已发送", tone: .success)
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError.isUnauthorized { session.handle(error); return }
            session.showToast("保存失败：\(apiError.localizedDescription)", tone: .danger)
        }
    }
}

struct NotificationSettingsView: View {

    @EnvironmentObject private var session: AppSession
    @StateObject private var viewModel = NotificationViewModel()

    var body: some View {
        content
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("通知设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存并测试") {
                        Task { await viewModel.save(session: session) }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .disabled(viewModel.isSaving)
                }
            }
            .refreshable { await viewModel.load(session: session) }
            .task { await viewModel.load(session: session) }
            .sheet(isPresented: $viewModel.showsChannelPicker) {
                channelPicker
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading where viewModel.values.isEmpty:
            LoadingView(text: "读取通知配置…")
        case .failed(let message) where viewModel.values.isEmpty:
            ScrollView {
                EmptyStateView(
                    symbol: "bell.slash",
                    title: "无法读取通知配置",
                    message: message,
                    actionTitle: "重试"
                ) { Task { await viewModel.load(session: session) } }
            }
        default:
            Form {
                Section {
                    Button {
                        viewModel.showsChannelPicker = true
                    } label: {
                        HStack(spacing: Theme.Spacing.medium) {
                            Image(systemName: viewModel.channel.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.brand)
                                .frame(width: 30, height: 30)
                                .background(Theme.brand.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewModel.channel.title)
                                    .font(Theme.Font.callout.weight(.medium))
                                    .foregroundColor(Theme.textPrimary)
                                Text("点击切换通知渠道")
                                    .font(Theme.Font.caption)
                                    .foregroundColor(Theme.textTertiary)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Theme.textTertiary)
                        }
                    }
                } header: {
                    SectionHeader(title: "通知渠道", subtitle: "共支持 \(NotificationCatalog.channels.count) 种渠道")
                }

                Section {
                    ForEach(viewModel.channel.fields) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.label)
                                .font(Theme.Font.caption)
                                .foregroundColor(Theme.textSecondary)

                            if field.kind == .multiline {
                                ZStack(alignment: .topLeading) {
                                    if viewModel.binding(for: field.key).wrappedValue.isEmpty {
                                        Text(field.placeholder)
                                            .font(Theme.Font.monoSmall)
                                            .foregroundColor(Theme.textTertiary)
                                            .padding(.top, 8)
                                            .padding(.leading, 4)
                                            .allowsHitTesting(false)
                                    }
                                    TextEditor(text: viewModel.binding(for: field.key))
                                        .font(Theme.Font.monoSmall)
                                        .frame(minHeight: 80)
                                }
                            } else if field.kind == .secure {
                                SecureField(field.placeholder, text: viewModel.binding(for: field.key))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .font(Theme.Font.monoSmall)
                            } else {
                                TextField(field.placeholder, text: viewModel.binding(for: field.key))
                                    .keyboardType(field.kind == .number ? .numberPad : .default)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .font(Theme.Font.monoSmall)
                            }

                            if let hint = field.hint {
                                Text(hint)
                                    .font(Theme.Font.caption)
                                    .foregroundColor(Theme.textTertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    SectionHeader(title: viewModel.channel.title, subtitle: "字段与面板保持一致，可留空")
                } footer: {
                    Text("点击右上角「保存并测试」后，面板会立即向该渠道发送一条测试消息；发送成功才会保存配置。")
                        .font(Theme.Font.caption)
                }
            }
            .listStyle(.insetGrouped)
            .overlay { if viewModel.isSaving { BlockingOverlay(text: "正在发送测试通知…") } }
        }
    }

    private var channelPicker: some View {
        NavigationView {
            List {
                ForEach(NotificationCatalog.channels) { channel in
                    Button {
                        viewModel.select(channel.type)
                        viewModel.showsChannelPicker = false
                    } label: {
                        HStack(spacing: Theme.Spacing.medium) {
                            Image(systemName: channel.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.brand)
                                .frame(width: 28, height: 28)
                                .background(Theme.brand.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            Text(channel.title)
                                .font(Theme.Font.callout)
                                .foregroundColor(Theme.textPrimary)

                            Spacer(minLength: 0)

                            if channel.type == viewModel.channelType {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Theme.brand)
                            }
                        }
                    }
                    .listRowBackground(Theme.surfaceElevated)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("选择通知渠道")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { viewModel.showsChannelPicker = false }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
