//
//  CronViewEditorView.swift
//  QingLong
//
//  创建 / 编辑任务视图。字段与面板 `viewCreateModal.tsx` 保持一致。
//

import SwiftUI

// MARK: - 编辑草稿

/// 编辑期的一条条件。用 UUID 作为 ForEach 的稳定标识，
/// 避免增删时 SwiftUI 复用错行。
struct CronViewFilterDraft: Identifiable, Equatable {
    let id: UUID
    var property: String
    var operation: String
    var text: String
    var statusValues: Set<Int>
    var subscriptionValues: Set<Int>

    init(
        id: UUID = UUID(),
        property: String = CronViewProperty.command.rawValue,
        operation: String = CronViewOperation.contains.rawValue,
        text: String = "",
        statusValues: Set<Int> = [],
        subscriptionValues: Set<Int> = []
    ) {
        self.id = id
        self.property = property
        self.operation = operation
        self.text = text
        self.statusValues = statusValues
        self.subscriptionValues = subscriptionValues
    }

    init(filter: CronViewFilter) {
        self.init(property: filter.property, operation: filter.operation)
        if property == CronViewProperty.status.rawValue {
            statusValues = Set(filter.valueList.compactMap { Int($0) })
            if !(CronViewOperation(rawValue: operation)?.isSelect ?? false) {
                operation = CronViewOperation.inside.rawValue
            }
        } else if property == CronViewProperty.subID.rawValue {
            subscriptionValues = Set(filter.valueList.compactMap { Int($0) })
            if !(CronViewOperation(rawValue: operation)?.isSelect ?? false) {
                operation = CronViewOperation.inside.rawValue
            }
        } else {
            text = filter.text
        }
    }

    var kind: CronViewProperty { CronViewProperty(rawValue: property) ?? .command }
    var isSelectOnly: Bool { kind.isSelectOnly }

    /// 状态 / 订阅只允许「属于 / 不属于」，其余保持用户选择
    var effectiveOperation: String {
        if isSelectOnly && !(CronViewOperation(rawValue: operation)?.isSelect ?? false) {
            return CronViewOperation.inside.rawValue
        }
        return operation
    }

    var availableOperations: [CronViewOperation] {
        isSelectOnly ? [.inside, .notInside] : CronViewOperation.allCases
    }

    var payload: CronViewFilter {
        if kind == .status {
            let values = statusValues.sorted().map { JSONValue.number(Double($0)) }
            return CronViewFilter(property: property, operation: effectiveOperation, value: .array(values))
        }
        if kind == .subID {
            let values = subscriptionValues.sorted().map { JSONValue.number(Double($0)) }
            return CronViewFilter(property: property, operation: effectiveOperation, value: .array(values))
        }
        return CronViewFilter(
            property: property,
            operation: effectiveOperation,
            value: .string(text.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }
}

// MARK: - ViewModel

@MainActor
final class CronViewEditorViewModel: ObservableObject {

    @Published var name: String = ""
    @Published var relation: String = "and"
    @Published var filters: [CronViewFilterDraft] = []
    @Published var sortField: String = ""
    @Published var sortAscending: Bool = true
    @Published var isSaving = false
    @Published var subscriptions: [QLSubscription] = []

    let editing: QLCronView?

    init(view: QLCronView?) {
        editing = view
        guard let view else {
            filters = [CronViewFilterDraft()]
            return
        }
        name = view.name
        relation = view.isOr ? "or" : "and"
        filters = view.filters.map(CronViewFilterDraft.init(filter:))
        if let sort = view.sorts.first {
            sortField = sort.value
            sortAscending = sort.isAscending
        }
    }

    var isEditing: Bool { editing != nil }

    /// 只有按订阅筛选时才需要订阅列表
    var needsSubscriptions: Bool {
        filters.contains { $0.kind == .subID }
    }

    func loadSubscriptions() async {
        guard subscriptions.isEmpty else { return }
        subscriptions = (try? await SubscriptionService.list()) ?? []
    }

    func addFilter() {
        filters.append(CronViewFilterDraft())
    }

    func removeFilter(id: UUID) {
        filters.removeAll { $0.id == id }
    }

    @discardableResult
    func save(session: AppSession) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            session.showToast("请先填写视图名称", tone: .warning)
            return false
        }
        isSaving = true
        defer { isSaving = false }

        let payloadFilters = filters.map(\.payload).filter(\.isUsable)
        let payloadSorts = sortField.isEmpty
            ? []
            : [CronViewSort(type: sortAscending ? "ASC" : "DESC", value: sortField)]

        do {
            if let editing {
                try await CronViewService.update(
                    id: editing.id,
                    name: trimmed,
                    filters: payloadFilters,
                    sorts: payloadSorts,
                    relation: relation
                )
            } else {
                try await CronViewService.create(
                    name: trimmed,
                    filters: payloadFilters,
                    sorts: payloadSorts,
                    relation: relation
                )
            }
            session.showToast(isEditing ? "已保存视图" : "已创建视图", tone: .success)
            return true
        } catch {
            session.handle(error)
            return false
        }
    }
}

// MARK: - 页面

struct CronViewEditorView: View {

    @EnvironmentObject private var session: AppSession
    @Environment(\.presentationMode) private var presentationMode

    @StateObject private var viewModel: CronViewEditorViewModel

    private let onSaved: () -> Void

    init(view: QLCronView?, onSaved: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: CronViewEditorViewModel(view: view))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationView {
            Form {
                nameSection
                conditionSection
                sortSection
            }
            .navigationTitle(viewModel.isEditing ? "编辑视图" : "创建视图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("保存").font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            .task(id: viewModel.needsSubscriptions) {
                // 只有用到「订阅」条件时才需要这份列表
                if viewModel.needsSubscriptions {
                    await viewModel.loadSubscriptions()
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 名称

    private var nameSection: some View {
        Section {
            TextField("例如：只看 YYB 相关任务", text: $viewModel.name)
                .autocorrectionDisabled(true)
            if viewModel.editing?.isSystem == true {
                Text("面板内置视图，名称与条件不可修改。")
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textTertiary)
            }
        } header: {
            Text("视图名称")
        } footer: {
            Text("视图会作为标签页出现在任务列表顶部，与面板网页端共用同一份数据。")
        }
    }

    // MARK: - 条件

    private var conditionSection: some View {
        Section {
            Picker("条件关系", selection: $viewModel.relation) {
                Text("同时满足").tag("and")
                Text("满足任一").tag("or")
            }
            .pickerStyle(.segmented)

            ForEach($viewModel.filters) { $draft in
                filterRow(draft: $draft)
            }

            Button {
                viewModel.addFilter()
            } label: {
                Label("添加条件", systemImage: "plus.circle.fill")
                    .font(Theme.Font.callout.weight(.medium))
                    .foregroundColor(Theme.brand)
            }
        } header: {
            Text("筛选条件")
        } footer: {
            if viewModel.filters.isEmpty {
                Text("不添加条件时，视图等同于「全部任务」。")
            } else {
                Text("「包含 / 不包含」用于命令、名称、定时规则与标签；状态与订阅只能「属于 / 不属于」。")
            }
        }
    }

    @ViewBuilder
    private func filterRow(draft: Binding<CronViewFilterDraft>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(spacing: Theme.Spacing.small) {
                Picker("字段", selection: draft.property) {
                    ForEach(CronViewProperty.allCases) { item in
                        Text(item.title).tag(item.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Picker("操作", selection: operationBinding(draft)) {
                    ForEach(draft.wrappedValue.availableOperations) { item in
                        Text(item.title).tag(item.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Spacer(minLength: 0)

                Button {
                    viewModel.removeFilter(id: draft.wrappedValue.id)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(Theme.danger)
                }
                .buttonStyle(.plain)
            }

            valueRow(draft: draft)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func valueRow(draft: Binding<CronViewFilterDraft>) -> some View {
        let kind = draft.wrappedValue.kind
        if kind == .status {
            statusSelector(draft: draft)
        } else if kind == .subID {
            subscriptionSelector(draft: draft)
        } else {
            TextField(valuePlaceholder(for: kind), text: draft.text)
                .font(Theme.Font.monoSmall)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
        }
    }

    private func valuePlaceholder(for kind: CronViewProperty) -> String {
        switch kind {
        case .command: return "命令关键字，例如 GO-Script"
        case .name: return "任务名称关键字"
        case .schedule: return "定时规则，例如 37 6"
        case .labels: return "标签关键字"
        case .status, .subID: return "值"
        }
    }

    private func statusSelector(draft: Binding<CronViewFilterDraft>) -> some View {
        HStack(spacing: Theme.Spacing.small) {
            ForEach(statusOptions) { option in
                let selected = draft.wrappedValue.statusValues.contains(option.id)
                CronViewChoiceChip(title: option.title, isSelected: selected) {
                    var values = draft.wrappedValue.statusValues
                    if selected {
                        values.remove(option.id)
                    } else {
                        values.insert(option.id)
                    }
                    draft.statusValues.wrappedValue = values
                }
            }
        }
    }

    private struct StatusOption: Identifiable {
        let id: Int
        let title: String
    }

    private var statusOptions: [StatusOption] {
        [
            StatusOption(id: CronStatus.running.rawValue, title: "运行中"),
            StatusOption(id: CronStatus.idle.rawValue, title: "空闲"),
            StatusOption(id: CronStatus.disabled.rawValue, title: "已禁用"),
            StatusOption(id: CronStatus.queued.rawValue, title: "排队中")
        ]
    }

    @ViewBuilder
    private func subscriptionSelector(draft: Binding<CronViewFilterDraft>) -> some View {
        if viewModel.subscriptions.isEmpty {
            HStack(spacing: Theme.Spacing.small) {
                Text("未读取到订阅列表")
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textTertiary)
                Button("重试") {
                    Task { await viewModel.loadSubscriptions() }
                }
                .font(Theme.Font.caption.weight(.semibold))
                .foregroundColor(Theme.brand)
            }
        } else {
            Menu {
                ForEach(viewModel.subscriptions) { subscription in
                    Button {
                        var values = draft.wrappedValue.subscriptionValues
                        if values.contains(subscription.id) {
                            values.remove(subscription.id)
                        } else {
                            values.insert(subscription.id)
                        }
                        draft.subscriptionValues.wrappedValue = values
                    } label: {
                        if draft.wrappedValue.subscriptionValues.contains(subscription.id) {
                            Label(subscription.title, systemImage: "checkmark")
                        } else {
                            Text(subscription.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: Theme.Spacing.small) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                    Text(subscriptionSelectionText(draft.wrappedValue))
                        .font(Theme.Font.callout)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(draft.wrappedValue.subscriptionValues.isEmpty ? Theme.textTertiary : Theme.brand)
            }
        }
    }

    private func subscriptionSelectionText(_ draft: CronViewFilterDraft) -> String {
        guard !draft.subscriptionValues.isEmpty else { return "选择订阅" }
        let names = viewModel.subscriptions
            .filter { draft.subscriptionValues.contains($0.id) }
            .map(\.title)
        return names.isEmpty ? "已选 \(draft.subscriptionValues.count) 项" : names.joined(separator: "、")
    }

    private func operationBinding(_ draft: Binding<CronViewFilterDraft>) -> Binding<String> {
        Binding(
            get: { draft.wrappedValue.effectiveOperation },
            set: { draft.wrappedValue.operation = $0 }
        )
    }

    // MARK: - 排序

    private var sortSection: some View {
        Section {
            Picker("排序字段", selection: $viewModel.sortField) {
                Text("不排序").tag("")
                ForEach(CronViewSortField.allCases) { field in
                    Text(field.title).tag(field.rawValue)
                }
            }
            if !viewModel.sortField.isEmpty {
                Picker("排序方向", selection: $viewModel.sortAscending) {
                    Text("升序").tag(true)
                    Text("降序").tag(false)
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("排序（可选）")
        } footer: {
            Text("默认按面板顺序：置顶在前、禁用在后。设置排序后以该字段优先。")
        }
    }

    private func save() async {
        let success = await viewModel.save(session: session)
        guard success else { return }
        onSaved()
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - 选择胶囊

struct CronViewChoiceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Group {
                        if isSelected {
                            Capsule().fill(Theme.brandGradient)
                        } else {
                            Capsule().fill(Theme.surfaceElevated)
                                .overlay(Capsule().stroke(Theme.stroke, lineWidth: 0.6))
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
}
