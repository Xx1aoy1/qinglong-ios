//
//  ServerEditView.swift
//  QingLong
//
//  新增 / 编辑面板地址。保存前会做一次连通性探测。
//

import SwiftUI

struct ServerEditView: View {

    let target: ServerEditTarget

    @EnvironmentObject private var session: AppSession
    @Environment(\.presentationMode) private var presentationMode

    @State private var alias: String = ""
    @State private var address: String = ""
    @State private var isProbing = false
    @State private var probeResult: SystemStatus?
    @State private var errorText: String?
    @FocusState private var addressFocused: Bool

    private var isEditing: Bool {
        if case .edit = target { return true }
        return false
    }

    private var addressError: String? {
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return ServerConfig.validate(address: address)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("例如：家里的群晖", text: $alias)
                        .textInputAutocapitalization(.never)
                } header: {
                    SectionHeader(title: "备注名称", subtitle: "可选，仅用于本机识别")
                }

                Section {
                    TextField("http://192.168.1.10:5700", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($addressFocused)

                    if let addressError {
                        Label(addressError, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Font.caption)
                            .foregroundColor(Theme.danger)
                    }
                } header: {
                    SectionHeader(title: "面板地址", subtitle: "可省略协议，默认按 http 处理")
                } footer: {
                    Text("若面板部署在子路径下（例如 https://example.com/ql），请把子路径一并填入。")
                        .font(Theme.Font.caption)
                }

                if let probeResult {
                    Section {
                        InfoRow(label: "面板版本", value: probeResult.version ?? "未知")
                        InfoRow(label: "分支", value: probeResult.branch ?? "—")
                        InfoRow(label: "发布时间", value: probeResult.publishDateText)
                        InfoRow(
                            label: "初始化",
                            value: probeResult.isInitialized == true ? "已完成" : "未完成（仍为默认账号）",
                            valueColor: probeResult.isInitialized == true ? Theme.success : Theme.warning
                        )
                    } header: {
                        SectionHeader(title: "连接测试成功")
                    }
                }

                if let errorText {
                    Section {
                        Label(errorText, systemImage: "xmark.octagon.fill")
                            .font(Theme.Font.callout)
                            .foregroundColor(Theme.danger)
                    }
                }

                Section {
                    Button {
                        Task { await probe() }
                    } label: {
                        HStack {
                            Spacer()
                            if isProbing {
                                ProgressView().scaleEffect(0.85)
                            }
                            Text(isProbing ? "测试中…" : "测试连接")
                            Spacer()
                        }
                    }
                    .disabled(isProbing || address.trimmed.isEmpty || addressError != nil)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(isEditing ? "编辑面板" : "添加面板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        Task { await save() }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .disabled(isProbing || address.trimmed.isEmpty || addressError != nil)
                }
            }
            .overlay {
                if isProbing {
                    BlockingOverlay(text: "正在连接面板…")
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear(perform: fill)
    }

    private func fill() {
        guard case .edit(let server) = target else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { addressFocused = true }
            return
        }
        alias = server.alias
        address = server.address
    }

    // MARK: - 动作

    private func probe() async {
        isProbing = true
        errorText = nil
        defer { isProbing = false }
        do {
            probeResult = try await session.probe(address: address)
        } catch {
            probeResult = nil
            errorText = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    private func save() async {
        isProbing = true
        errorText = nil
        defer { isProbing = false }

        do {
            let id: UUID? = {
                if case .edit(let server) = target { return server.id }
                return nil
            }()
            let server = try await session.addOrUpdateServer(
                id: id,
                address: address,
                alias: alias.trimmed
            )
            session.showToast("已保存：\(server.displayName)", tone: .success)
            presentationMode.wrappedValue.dismiss()

            // 引导流程：保存后直接切换过去
            if !session.phase.isReady {
                session.switchTo(server: server)
            }
        } catch {
            errorText = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}
