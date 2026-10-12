//
//  OpenAppsView.swift
//  QingLong
//
//  面板「开放接口」应用管理（client_id / client_secret）。
//  适合给第三方脚本或自建服务发放受限 Token，而不必暴露账号密码。
//

import SwiftUI
import UIKit

@MainActor
final class OpenAppsViewModel: ObservableObject {

    @Published var apps: [QLOpenApp] = []
    @Published var state: LoadState = .idle
    @Published var isWorking = false

    func load(session: AppSession, silent: Bool = false) async {
        if !silent, case .idle = state { state = .loading }
        do {
            apps = try await SystemService.apps()
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            if apiError.isUnauthorized { session.handle(error); return }
            state = .failed(apiError.localizedDescription)
        }
    }

    func perform(session: AppSession, _ action: @escaping () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await action()
            await load(session: session, silent: true)
        } catch {
            session.handle(error)
        }
    }
}

struct OpenAppsView: View {

    @EnvironmentObject private var session: AppSession
    @StateObject private var viewModel = OpenAppsViewModel()

    @State private var editing: QLOpenApp?
    @State private var showsCreate = false
    @State private var pendingDelete: QLOpenApp?

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading where viewModel.apps.isEmpty:
                LoadingView(text: "读取应用列表…")
            case .failed(let message) where viewModel.apps.isEmpty:
                ScrollView {
                    EmptyStateView(
                        symbol: "link.badge.plus",
                        title: "无法读取应用列表",
                        message: message,
                        actionTitle: "重试"
                    ) { Task { await viewModel.load(session: session) } }
                }
            default:
                if viewModel.apps.isEmpty {
                    ScrollView {
                        EmptyStateView(
                            symbol: "link.circle",
                            title: "还没有开放接口应用",
                            message: "创建应用后会得到 client_id 与 client_secret，可用它换取受限 Token。",
                            actionTitle: "创建应用"
                        ) { showsCreate = true }
                    }
                } else {
                    List {
                        Section {
                            ForEach(viewModel.apps) { app in
                                OpenAppRow(app: app)
                                    .listRowBackground(Theme.surfaceElevated)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editing = app }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            pendingDelete = app
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                        Button {
                                            Task {
                                                await viewModel.perform(session: session) {
                                                    try await SystemService.resetAppSecret(id: app.id)
                                                }
                                                session.showToast("已重置密钥", tone: .success)
                                            }
                                        } label: {
                                            Label("重置密钥", systemImage: "key")
                                        }
                                        .tint(Theme.warning)
                                    }
                            }
                        } header: {
                            SectionHeader(
                                title: "开放接口应用",
                                subtitle: "Token 有效期由面板控制，过期后需重新获取"
                            )
                        } footer: {
                            Text("获取 Token：GET /open/auth/token?client_id=…&client_secret=…，随后以其返回的 token 作为 Bearer 调用 /open/* 接口。")
                                .font(Theme.Font.caption)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("开放接口")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showsCreate = true } label: {
                    Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .refreshable { await viewModel.load(session: session) }
        .task { await viewModel.load(session: session) }
        .sheet(isPresented: $showsCreate) {
            OpenAppEditView(app: nil).environmentObject(session)
        }
        .sheet(item: $editing) { app in
            OpenAppEditView(app: app).environmentObject(session)
        }
        .alert(item: $pendingDelete) { app in
            Alert(
                title: Text("删除应用"),
                message: Text("删除「\(app.title)」后，其已签发的 Token 将全部失效。"),
                primaryButton: .destructive(Text("删除")) {
                    Task {
                        await viewModel.perform(session: session) {
                            try await SystemService.deleteApps([app.id])
                        }
                        session.showToast("已删除应用", tone: .success)
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .overlay { if viewModel.isWorking { BlockingOverlay(text: "处理中…") } }
    }
}

struct OpenAppRow: View {
    let app: QLOpenApp

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(app.title)
                    .font(Theme.Font.headline)
                    .foregroundColor(Theme.textPrimary)
                Spacer(minLength: 0)
                StatusPill(
                    text: "\(app.activeTokenCount) 个有效 Token",
                    tone: app.activeTokenCount > 0 ? .success : .neutral,
                    compact: true
                )
            }

            if let clientId = app.client_id {
                Text("client_id  \(clientId)")
                    .font(Theme.Font.monoSmall)
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
            }

            if !app.scopeList.isEmpty {
                WrapHStack(spacing: 5) {
                    ForEach(app.scopeList, id: \.rawValue) { scope in
                        TagChip(text: scope.title, color: Theme.info)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 新建 / 编辑

struct OpenAppEditView: View {

    let app: QLOpenApp?

    @EnvironmentObject private var session: AppSession
    @Environment(\.presentationMode) private var presentationMode

    @State private var name = ""
    @State private var scopes: Set<AppScope> = [.crons, .envs, .logs, .scripts]
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("应用名称", text: $name)
                        .textInputAutocapitalization(.never)
                } header: {
                    SectionHeader(title: "名称")
                }

                Section {
                    ForEach(AppScope.allCases, id: \.rawValue) { scope in
                        Button {
                            if scopes.contains(scope) {
                                scopes.remove(scope)
                            } else {
                                scopes.insert(scope)
                            }
                        } label: {
                            HStack {
                                Text(scope.title)
                                    .foregroundColor(Theme.textPrimary)
                                Spacer()
                                Image(systemName: scopes.contains(scope) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(scopes.contains(scope) ? Theme.brand : Theme.textTertiary)
                            }
                        }
                    }
                } header: {
                    SectionHeader(title: "授权范围", subtitle: "决定该应用可以访问哪些接口分组")
                }

                if let app, let secret = app.client_secret {
                    Section {
                        InfoRow(label: "client_id", value: app.client_id ?? "—", mono: true)
                        InfoRow(label: "client_secret", value: secret, mono: true)
                        Button {
                            UIPasteboard.general.string = secret
                            session.showToast("已复制密钥", tone: .success)
                        } label: {
                            Label("复制密钥", systemImage: "doc.on.doc")
                        }
                    } header: {
                        SectionHeader(title: "凭证", subtitle: "请妥善保管，不要提交到公开仓库")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(app == nil ? "创建应用" : "应用详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { Task { await save() } }
                        .font(.system(size: 16, weight: .semibold))
                        .disabled(name.trimmed.isEmpty || scopes.isEmpty || isSaving)
                }
            }
            .overlay { if isSaving { BlockingOverlay(text: "保存中…") } }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            guard let app else { return }
            name = app.name ?? ""
            scopes = Set(app.scopeList)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let scopeValues = scopes.map(\.rawValue).sorted()
            if let app {
                try await SystemService.updateApp(id: app.id, name: name.trimmed, scopes: scopeValues)
            } else {
                try await SystemService.createApp(name: name.trimmed, scopes: scopeValues)
            }
            session.showToast("已保存", tone: .success)
            presentationMode.wrappedValue.dismiss()
        } catch {
            session.handle(error)
        }
    }
}
