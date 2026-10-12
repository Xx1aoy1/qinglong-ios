//
//  EnvEditView.swift
//  QingLong
//
//  环境变量新建 / 编辑 / 详情 / 导入。
//

import SwiftUI
import UIKit

// MARK: - 新建 / 编辑

struct EnvEditView: View {

    enum Target {
        case create
        case edit(QLEnv)

        var env: QLEnv? {
            if case .edit(let env) = self { return env }
            return nil
        }

        var isEdit: Bool { env != nil }
    }

    let target: Target

    @EnvironmentObject private var session: AppSession
    @Environment(\.presentationMode) private var presentationMode

    @State private var name = ""
    @State private var value = ""
    @State private var remarks = ""
    @State private var labelsText = ""
    @State private var batchText = ""
    @State private var useBatchMode = false
    @State private var isSaving = false
    @State private var errorText: String?

    private var nameError: String? {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else { return nil }
        let pattern = "^[a-zA-Z_][0-9a-zA-Z_]*$"
        return trimmed.range(of: pattern, options: .regularExpression) == nil
            ? "变量名只能包含字母、数字、下划线，且不能以数字开头"
            : nil
    }

    private var canSave: Bool {
        if useBatchMode && !target.isEdit {
            return batchText.trimmed.nonEmptyLines.contains { $0.contains("=") }
        }
        return !name.trimmed.isEmpty && !value.isEmpty && nameError == nil
    }

    var body: some View {
        NavigationView {
            Form {
                if !target.isEdit {
                    Section {
                        Toggle(isOn: $useBatchMode) {
                            Text("批量添加（每行一个 name=value）")
                                .font(Theme.Font.callout)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Theme.brand))
                    }
                }

                if useBatchMode && !target.isEdit {
                    Section {
                        ZStack(alignment: .topLeading) {
                            if batchText.isEmpty {
                                Text("COOKIE=abc123\nTOKEN=xyz789")
                                    .font(Theme.Font.mono)
                                    .foregroundColor(Theme.textTertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $batchText)
                                .font(Theme.Font.mono)
                                .frame(minHeight: 160)
                        }
                    } header: {
                        SectionHeader(title: "批量内容", subtitle: "支持 # 开头的注释行与空行")
                    }
                } else {
                    Section {
                        TextField("变量名，例如 JD_COOKIE", text: $name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(Theme.Font.mono)

                        if let nameError {
                            Label(nameError, systemImage: "exclamationmark.triangle.fill")
                                .font(Theme.Font.caption)
                                .foregroundColor(Theme.danger)
                        }

                        ZStack(alignment: .topLeading) {
                            if value.isEmpty {
                                Text("变量值")
                                    .font(Theme.Font.callout)
                                    .foregroundColor(Theme.textTertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $value)
                                .font(Theme.Font.mono)
                                .frame(minHeight: 110)
                        }
                    } header: {
                        SectionHeader(title: "变量内容")
                    } footer: {
                        Text("值较长（如 Cookie）时建议直接粘贴，编辑器会自动换行显示。")
                            .font(Theme.Font.caption)
                    }
                }

                Section {
                    TextField("备注（可选）", text: $remarks)
                    TextField("标签，多个用逗号分隔", text: $labelsText)
                } header: {
                    SectionHeader(title: "附加信息")
                }

                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Font.callout)
                            .foregroundColor(Theme.danger)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(target.isEdit ? "编辑变量" : "新建变量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { Task { await save() } }
                        .font(.system(size: 16, weight: .semibold))
                        .disabled(!canSave || isSaving)
                }
            }
            .overlay { if isSaving { BlockingOverlay(text: "保存中…") } }
        }
        .navigationViewStyle(.stack)
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let env = target.env else { return }
        name = env.name
        value = env.value
        remarks = env.remarks ?? ""
        labelsText = env.labelList.joined(separator: ",")
    }

    private func parseLabels() -> [String] {
        labelsText
            .replacingOccurrences(of: "，", with: ",")
            .split(separator: ",")
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, label in
                if !result.contains(label) { result.append(label) }
            }
    }

    private func save() async {
        isSaving = true
        errorText = nil
        defer { isSaving = false }

        do {
            if useBatchMode && !target.isEdit {
                let payloads = parseBatch()
                guard !payloads.isEmpty else {
                    errorText = "没有解析到合法的变量，请检查格式（name=value）"
                    return
                }
                let created = try await EnvService.create(payloads)
                session.showToast("已添加 \(created.count) 个变量", tone: .success)
            } else if let env = target.env {
                try await EnvService.update(
                    EnvUpdatePayload(
                        id: env.id,
                        name: name.trimmed,
                        value: value,
                        remarks: remarks.trimmed,
                        labels: parseLabels()
                    )
                )
                session.showToast("变量已更新", tone: .success)
            } else {
                _ = try await EnvService.create(
                    name: name.trimmed,
                    value: value,
                    remarks: remarks.trimmed,
                    labels: parseLabels()
                )
                session.showToast("变量已创建", tone: .success)
            }
            presentationMode.wrappedValue.dismiss()
        } catch {
            errorText = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    private func parseBatch() -> [EnvCreatePayload] {
        var result: [EnvCreatePayload] = []
        let labels = parseLabels()
        for line in batchText.components(separatedBy: .newlines) {
            let trimmed = line.trimmed
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let index = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[trimmed.startIndex..<index]).trimmed
            let value = String(trimmed[trimmed.index(after: index)...])
            guard !key.isEmpty, !value.isEmpty else { continue }
            guard key.range(of: "^[a-zA-Z_][0-9a-zA-Z_]*$", options: .regularExpression) != nil else { continue }
            result.append(EnvCreatePayload(name: key, value: value, remarks: "", labels: labels))
        }
        return result
    }
}

// MARK: - 详情

struct EnvDetailView: View {

    let env: QLEnv

    @EnvironmentObject private var session: AppSession
    @Environment(\.presentationMode) private var presentationMode

    @State private var revealed = false
    @State private var current: QLEnv?
    @State private var showsEditor = false
    @State private var isWorking = false

    private var item: QLEnv { current ?? env }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.large) {
                VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(Theme.Font.headline)
                            .foregroundColor(Theme.textPrimary)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        StatusPill(text: item.statusValue.title, tone: item.statusValue.tone, compact: true)
                    }

                    if !item.labelList.isEmpty {
                        WrapHStack(spacing: 5) {
                            ForEach(item.labelList, id: \.self) { TagChip(text: $0) }
                        }
                    }

                    Divider().background(Theme.separator)

                    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                        HStack {
                            Text("变量值")
                                .font(Theme.Font.caption)
                                .foregroundColor(Theme.textTertiary)
                            Spacer()
                            Button {
                                revealed.toggle()
                            } label: {
                                Label(revealed ? "隐藏" : "显示", systemImage: revealed ? "eye.slash" : "eye")
                                    .font(Theme.Font.caption.weight(.semibold))
                                    .foregroundColor(Theme.brand)
                            }
                            Button {
                                UIPasteboard.general.string = item.value
                                session.showToast("已复制变量值", tone: .success)
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                                    .font(Theme.Font.caption.weight(.semibold))
                                    .foregroundColor(Theme.brand)
                            }
                        }

                        Text(revealed ? item.value : String(repeating: "•", count: min(item.value.count, 60)))
                            .font(Theme.Font.mono)
                            .foregroundColor(Theme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Spacing.medium)
                            .background(Theme.surfaceSunken)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                    }
                }
                .qlCard()

                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    SectionHeader(title: "详细信息")
                    InfoRow(label: "变量 ID", value: "\(item.id)", mono: true)
                    InfoRow(label: "备注", value: item.remarks ?? "—")
                    InfoRow(label: "创建时间", value: item.timestamp ?? "—")
                    InfoRow(label: "状态", value: item.isDisabled ? "已禁用" : "已启用")
                }
                .qlCard()

                VStack(spacing: Theme.Spacing.medium) {
                    Button {
                        showsEditor = true
                    } label: {
                        Label("编辑变量", systemImage: "pencil").qlSecondaryButton()
                    }
                    .buttonStyle(.pressable)

                    Button {
                        Task { await toggleEnabled() }
                    } label: {
                        Label(
                            item.isDisabled ? "启用变量" : "禁用变量",
                            systemImage: item.isDisabled ? "checkmark.circle" : "pause.circle"
                        )
                        .qlSecondaryButton()
                    }
                    .buttonStyle(.pressable)

                    Button {
                        Task { await remove() }
                    } label: {
                        Label("删除变量", systemImage: "trash")
                            .font(Theme.Font.headline)
                            .foregroundColor(Theme.danger)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Theme.danger.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(Theme.Spacing.large)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("变量详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsEditor) {
            EnvEditView(target: .edit(item)).environmentObject(session)
        }
        .overlay { if isWorking { BlockingOverlay(text: "处理中…") } }
        .task { await refresh() }
    }

    private func refresh() async {
        guard let list = try? await EnvService.list() else { return }
        current = list.first { $0.id == env.id }
    }

    private func toggleEnabled() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await EnvService.setEnabled(ids: [item.id], enabled: item.isDisabled)
            await refresh()
            session.showToast(item.isDisabled ? "已禁用" : "已启用", tone: .info)
        } catch {
            session.handle(error)
        }
    }

    private func remove() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await EnvService.remove(ids: [item.id])
            session.showToast("已删除变量", tone: .success)
            presentationMode.wrappedValue.dismiss()
        } catch {
            session.handle(error)
        }
    }
}

// MARK: - 导入

struct EnvImportView: View {

    @EnvironmentObject private var session: AppSession
    @Environment(\.presentationMode) private var presentationMode

    @State private var text = ""
    @State private var isImporting = false
    @State private var errorText: String?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("[{\"name\":\"JD_COOKIE\",\"value\":\"pt_key=...\",\"remarks\":\"\"}]")
                                .font(Theme.Font.monoSmall)
                                .foregroundColor(Theme.textTertiary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $text)
                            .font(Theme.Font.monoSmall)
                            .frame(minHeight: 180)
                    }
                } header: {
                    SectionHeader(title: "粘贴 JSON", subtitle: "与面板「导出环境变量」格式一致")
                } footer: {
                    Text("也可以粘贴 `name=value` 形式的多行文本，每行一个。")
                        .font(Theme.Font.caption)
                }

                Section {
                    Button {
                        if let clipboard = UIPasteboard.general.string {
                            text = clipboard
                        }
                    } label: {
                        Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                    }

                    Button {
                        Task { await doImport() }
                    } label: {
                        HStack {
                            Spacer()
                            Text(isImporting ? "导入中…" : "开始导入")
                            Spacer()
                        }
                    }
                    .disabled(text.trimmed.isEmpty || isImporting)
                }

                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Font.callout)
                            .foregroundColor(Theme.danger)
                    }
                }
            }
            .navigationTitle("导入环境变量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .overlay { if isImporting { BlockingOverlay(text: "导入中…") } }
        }
        .navigationViewStyle(.stack)
    }

    private func doImport() async {
        isImporting = true
        errorText = nil
        defer { isImporting = false }

        do {
            let trimmed = text.trimmed
            if trimmed.hasPrefix("[") {
                let data = Data(trimmed.utf8)
                let count = try await EnvService.importJSON(data)
                session.showToast("已导入 \(count) 个变量", tone: .success)
            } else {
                let payloads = trimmed.nonEmptyLines.compactMap { line -> EnvCreatePayload? in
                    guard let index = line.firstIndex(of: "=") else { return nil }
                    let key = String(line[line.startIndex..<index]).trimmed
                    let value = String(line[line.index(after: index)...])
                    guard !key.isEmpty, !value.isEmpty else { return nil }
                    return EnvCreatePayload(name: key, value: value, remarks: "", labels: [])
                }
                guard !payloads.isEmpty else {
                    errorText = "没有解析到合法内容"
                    return
                }
                let created = try await EnvService.create(payloads)
                session.showToast("已导入 \(created.count) 个变量", tone: .success)
            }
            presentationMode.wrappedValue.dismiss()
        } catch {
            errorText = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}
