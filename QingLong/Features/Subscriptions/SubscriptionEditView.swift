//
//  SubscriptionEditView.swift
//  QingLong
//
//  订阅的新建 / 编辑 / 详情。
//

import SwiftUI
import UIKit

struct SubscriptionEditView: View {

    enum Target {
        case create
        case edit(QLSubscription)

        var item: QLSubscription? {
            if case .edit(let item) = self { return item }
            return nil
        }

        var isEdit: Bool { item != nil }
    }

    let target: Target

    @EnvironmentObject private var session: AppSession
    @Environment(\.presentationMode) private var presentationMode

    @State private var type: SubscriptionType = .publicRepo
    @State private var alias = ""
    @State private var url = ""
    @State private var scheduleType: SubscriptionScheduleType = .crontab
    @State private var schedule = "0 0 * * *"
    @State private var intervalUnit: IntervalUnit = .hours
    @State private var intervalValue = "6"
    @State private var branch = ""
    @State private var whitelist = ""
    @State private var blacklist = ""
    @State private var dependences = ""
    @State private var extensions = ""
    @State private var subBefore = ""
    @State private var subAfter = ""
    @State private var proxy = ""
    @State private var autoAddCron = true
    @State private var autoDelCron = true

    @State private var isSaving = false
    @State private var errorText: String?

    init(target: Target) {
        self.target = target
        if let item = target.item {
            _type = State(initialValue: item.typeValue)
            _alias = State(initialValue: item.alias)
            _url = State(initialValue: item.url)
            _scheduleType = State(initialValue: item.scheduleTypeValue)
            _schedule = State(initialValue: item.schedule ?? "0 0 * * *")
            _intervalUnit = State(initialValue: item.interval_schedule?.unit ?? .hours)
            _intervalValue = State(initialValue: String(item.interval_schedule?.value ?? 6))
            _branch = State(initialValue: item.branch ?? "")
            _whitelist = State(initialValue: item.whitelist ?? "")
            _blacklist = State(initialValue: item.blacklist ?? "")
            _dependences = State(initialValue: item.dependences ?? "")
            _extensions = State(initialValue: item.extensions ?? "")
            _subBefore = State(initialValue: item.sub_before ?? "")
            _subAfter = State(initialValue: item.sub_after ?? "")
            _proxy = State(initialValue: item.proxy ?? "")
            _autoAddCron = State(initialValue: item.autoAddCron != 0)
            _autoDelCron = State(initialValue: item.autoDelCron != 0)
        }
    }

    private var canSave: Bool {
        !url.trimmed.isEmpty && !alias.trimmed.isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                typeSection
                sourceSection
                scheduleSection
                filterSection
                advancedSection

                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Font.callout)
                            .foregroundColor(Theme.danger)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(target.isEdit ? "编辑订阅" : "新建订阅")
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
    }

    // MARK: - 区块

    private var typeSection: some View {
        Section {
            Picker("订阅类型", selection: $type) {
                ForEach(SubscriptionType.allCases, id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            TextField("别名（必填，用于识别本订阅）", text: $alias)
        } header: {
            SectionHeader(title: "基础")
        } footer: {
            Text(type == .file
                 ? "单文件模式：直接拉取一个脚本文件到脚本目录。"
                 : "仓库模式：克隆 Git 仓库并可按白名单/黑名单筛选脚本。")
        }
    }

    private var sourceSection: some View {
        Section {
            TextField("仓库或文件地址（https / git）", text: $url)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .font(Theme.Font.monoSmall)

            if type != .file {
                TextField("分支（默认 master）", text: $branch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            }

            TextField("代理地址（可留空）", text: $proxy)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        } header: {
            SectionHeader(title: "来源")
        }
    }

    private var scheduleSection: some View {
        Section {
            Picker("调度方式", selection: $scheduleType) {
                ForEach(SubscriptionScheduleType.allCases, id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if scheduleType == .crontab {
                TextField("cron 表达式", text: $schedule)
                    .font(Theme.Font.mono)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(SchedulePreset.all.filter { !$0.value.hasPrefix("@") }) { preset in
                            TagChip(
                                text: preset.title,
                                color: schedule == preset.value ? Theme.brand : Theme.textSecondary
                            ) { schedule = preset.value }
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                HStack {
                    TextField("间隔数值", text: $intervalValue)
                        .keyboardType(.numberPad)
                        .frame(width: 90)

                    Picker("单位", selection: $intervalUnit) {
                        ForEach(IntervalUnit.allCases, id: \.self) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        } header: {
            SectionHeader(title: "拉取频率")
        }
    }

    private var filterSection: some View {
        Section {
            TextField("白名单（支持正则，多个用 & 分隔）", text: $whitelist)
                .font(Theme.Font.monoSmall)
            TextField("黑名单（支持正则，多个用 & 分隔）", text: $blacklist)
                .font(Theme.Font.monoSmall)
        } header: {
            SectionHeader(title: "脚本筛选")
        } footer: {
            Text("留空表示拉取仓库内全部脚本。使用白名单可只保留需要的脚本，显著减少任务数量。")
                .font(Theme.Font.caption)
        }
    }

    private var advancedSection: some View {
        Section {
            TextField("自动安装依赖（多个用 & 分隔）", text: $dependences)
                .font(Theme.Font.monoSmall)
            TextField("重命名后缀（扩展名过滤）", text: $extensions)
                .font(Theme.Font.monoSmall)
            TextField("拉取前置命令", text: $subBefore)
                .font(Theme.Font.monoSmall)
            TextField("拉取后置命令", text: $subAfter)
                .font(Theme.Font.monoSmall)

            Toggle(isOn: $autoAddCron) {
                Text("自动新增定时任务").font(Theme.Font.callout)
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.brand))

            Toggle(isOn: $autoDelCron) {
                Text("自动删除失效任务").font(Theme.Font.callout)
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.brand))
        } header: {
            SectionHeader(title: "高级选项")
        }
    }

    // MARK: - 保存

    private func save() async {
        isSaving = true
        errorText = nil
        defer { isSaving = false }

        let payload = SubscriptionPayload(
            id: target.item?.id,
            type: type.rawValue,
            schedule_type: scheduleType.rawValue,
            schedule: scheduleType == .crontab ? schedule.trimmed : "",
            interval_schedule: scheduleType == .interval
                ? IntervalSchedule(type: intervalUnit.rawValue, value: Int(intervalValue) ?? 1)
                : nil,
            name: alias.trimmed,
            alias: alias.trimmed,
            url: url.trimmed,
            whitelist: whitelist.nilIfEmpty,
            blacklist: blacklist.nilIfEmpty,
            branch: branch.nilIfEmpty,
            dependences: dependences.nilIfEmpty,
            extensions: extensions.nilIfEmpty,
            sub_before: subBefore.nilIfEmpty,
            sub_after: subAfter.nilIfEmpty,
            proxy: proxy.nilIfEmpty,
            autoAddCron: autoAddCron,
            autoDelCron: autoDelCron,
            pull_type: target.item?.pull_type,
            pull_option: nil
        )

        do {
            if target.isEdit {
                try await SubscriptionService.update(payload)
            } else {
                try await SubscriptionService.create(payload)
            }
            session.showToast(target.isEdit ? "订阅已更新" : "订阅已创建", tone: .success)
            presentationMode.wrappedValue.dismiss()
        } catch {
            errorText = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}

// MARK: - 详情

struct SubscriptionDetailView: View {

    let item: QLSubscription

    @EnvironmentObject private var session: AppSession
    @Environment(\.presentationMode) private var presentationMode

    @State private var showsEditor = false
    @State private var isWorking = false
    @State private var showsDeleteConfirm = false
    @State private var current: QLSubscription?

    private var subscription: QLSubscription { current ?? item }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.large) {
                VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                    HStack(spacing: Theme.Spacing.medium) {
                        ZStack {
                            Circle()
                                .fill(subscription.statusValue.tone.color.opacity(0.14))
                                .frame(width: 44, height: 44)
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(subscription.statusValue.tone.color)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(subscription.title)
                                .font(Theme.Font.headline)
                                .foregroundColor(Theme.textPrimary)
                            StatusPill(
                                text: subscription.statusValue.title,
                                tone: subscription.statusValue.tone,
                                compact: true
                            )
                        }
                        Spacer(minLength: 0)
                    }

                    Text(subscription.url)
                        .font(Theme.Font.monoSmall)
                        .foregroundColor(Theme.textSecondary)
                        .textSelection(.enabled)
                }
                .qlCard()

                HStack(spacing: Theme.Spacing.medium) {
                    ActionTile(
                        title: subscription.statusValue == .running ? "停止" : "拉取",
                        symbol: subscription.statusValue == .running ? "stop.fill" : "arrow.down.circle.fill",
                        tone: subscription.statusValue == .running ? .danger : .success
                    ) {
                        Task {
                            await perform {
                                if subscription.statusValue == .running {
                                    try await SubscriptionService.stop(ids: [subscription.id])
                                } else {
                                    try await SubscriptionService.run(ids: [subscription.id])
                                }
                            }
                        }
                    }
                    ActionTile(title: "编辑", symbol: "pencil", tone: .info) { showsEditor = true }
                    ActionTile(
                        title: subscription.statusValue == .disabled ? "启用" : "禁用",
                        symbol: subscription.statusValue == .disabled ? "checkmark.circle.fill" : "pause.circle.fill",
                        tone: subscription.statusValue == .disabled ? .success : .warning
                    ) {
                        let enable = subscription.statusValue == .disabled
                        Task {
                            await perform {
                                try await SubscriptionService.setEnabled(ids: [subscription.id], enabled: enable)
                            }
                        }
                    }
                }

                NavigationLink {
                    LogConsoleView(title: "订阅日志", subtitle: subscription.title) { offset, limit, tail in
                        try await SubscriptionService.log(
                            id: subscription.id,
                            offset: offset,
                            limit: limit,
                            tail: tail
                        )
                    }
                    .environmentObject(session)
                } label: {
                    NavigationRow(
                        symbol: "doc.text.magnifyingglass",
                        title: "拉取日志",
                        subtitle: "查看最近一次拉取的完整输出",
                        tone: .progress
                    )
                }
                .buttonStyle(.pressable)

                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    SectionHeader(title: "详细信息")
                    InfoRow(label: "订阅 ID", value: "\(subscription.id)", mono: true)
                    InfoRow(label: "类型", value: subscription.typeValue.title)
                    InfoRow(label: "调度", value: subscription.scheduleDescription, mono: true)
                    InfoRow(label: "分支", value: subscription.branch ?? "—")
                    InfoRow(label: "白名单", value: subscription.whitelist ?? "—", mono: true)
                    InfoRow(label: "黑名单", value: subscription.blacklist ?? "—", mono: true)
                    InfoRow(label: "依赖", value: subscription.dependences ?? "—", mono: true)
                    InfoRow(label: "自动新增任务", value: subscription.isAutoAddCron ? "是" : "否")
                    InfoRow(label: "自动删除任务", value: subscription.isAutoDelCron ? "是" : "否")
                    if let proxy = subscription.proxy, !proxy.isEmpty {
                        InfoRow(label: "代理", value: proxy, mono: true)
                    }
                }
                .qlCard()

                Button(role: .destructive) {
                    showsDeleteConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("删除订阅")
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
            .padding(Theme.Spacing.large)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("订阅详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsEditor) {
            SubscriptionEditView(target: .edit(subscription)).environmentObject(session)
        }
        .alert(isPresented: $showsDeleteConfirm) {
            Alert(
                title: Text("删除订阅"),
                message: Text("确定删除该订阅吗？"),
                primaryButton: .destructive(Text("删除")) {
                    Task {
                        await perform {
                            try await SubscriptionService.remove(ids: [subscription.id])
                        }
                        presentationMode.wrappedValue.dismiss()
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .overlay { if isWorking { BlockingOverlay(text: "处理中…") } }
        .task { await refresh() }
    }

    private func refresh() async {
        guard let list = try? await SubscriptionService.list() else { return }
        current = list.first { $0.id == item.id }
    }

    private func perform(_ action: @escaping () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await action()
            try? await Task.sleep(nanoseconds: 400_000_000)
            await refresh()
        } catch {
            session.handle(error)
        }
    }
}
