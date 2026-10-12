//
//  CronEditView.swift
//  QingLong
//
//  新建 / 编辑定时任务。
//

import SwiftUI

struct CronEditView: View {

    enum Target {
        case create
        case edit(QLCron)

        var cron: QLCron? {
            if case .edit(let cron) = self { return cron }
            return nil
        }

        var isEdit: Bool { cron != nil }
    }

    let target: Target

    @EnvironmentObject private var session: AppSession
    @Environment(\.presentationMode) private var presentationMode

    @State private var name = ""
    @State private var command = ""
    @State private var schedule = ""
    @State private var labelsText = ""
    @State private var logName = ""
    @State private var workDir = ""
    @State private var taskBefore = ""
    @State private var taskAfter = ""
    @State private var allowMultipleInstances = false

    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        NavigationView {
            Form {
                basicSection
                scheduleSection
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
            .navigationTitle(target.isEdit ? "编辑任务" : "新建任务")
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

    // MARK: - 表单区块

    private var basicSection: some View {
        Section {
            TextField("任务名称，例如「签到」", text: $name)

            ZStack(alignment: .topLeading) {
                if command.isEmpty {
                    Text("要执行的命令，例如：\n task hello.js  或  node /ql/scripts/demo.js")
                        .font(Theme.Font.callout)
                        .foregroundColor(Theme.textTertiary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $command)
                    .font(Theme.Font.mono)
                    .frame(minHeight: 96)
                    .disabled(false)
            }

            TextField("标签，多个用英文逗号分隔", text: $labelsText)
        } header: {
            SectionHeader(title: "基本信息")
        } footer: {
            Text("命令支持面板提供的 ql / task 前缀，例如 `ql repo`、`task demo.js`。")
                .font(Theme.Font.caption)
        }
    }

    private var scheduleSection: some View {
        Section {
            TextField("cron 表达式，例如 0 8 * * *", text: $schedule)
                .font(Theme.Font.mono)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SchedulePreset.all) { preset in
                        TagChip(
                            text: preset.title,
                            color: schedule == preset.value ? Theme.brand : Theme.textSecondary
                        ) {
                            schedule = preset.value
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            SectionHeader(title: "定时规则", subtitle: "支持标准 5 段 cron、@once、@boot")
        } footer: {
            VStack(alignment: .leading, spacing: 3) {
                Text("分钟 小时 日 月 周 — 例如 `*/5 * * * *` 表示每 5 分钟。")
                Text("`@once` 表示只在手动触发时运行一次；`@boot` 表示容器启动时运行。")
            }
            .font(Theme.Font.caption)
        }
    }

    private var advancedSection: some View {
        Section {
            TextField("自定义日志文件名（可留空）", text: $logName)
            TextField("工作目录（可留空）", text: $workDir)
            TextField("前置命令（可留空）", text: $taskBefore)
            TextField("后置命令（可留空）", text: $taskAfter)

            Toggle(isOn: $allowMultipleInstances) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("允许同时运行多个实例")
                        .font(Theme.Font.callout)
                    Text("关闭时，任务运行中不会被重复触发")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.textTertiary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.brand))
        } header: {
            SectionHeader(title: "高级选项")
        }
    }

    // MARK: - 逻辑

    private var canSave: Bool {
        !command.trimmed.isEmpty && !schedule.trimmed.isEmpty
    }

    private func fill() {
        guard let cron = target.cron else { return }
        name = cron.name ?? ""
        command = cron.command
        schedule = cron.schedule ?? ""
        labelsText = cron.labelList.joined(separator: ",")
        logName = cron.log_name ?? ""
        workDir = cron.work_dir ?? ""
        taskBefore = cron.task_before ?? ""
        taskAfter = cron.task_after ?? ""
        allowMultipleInstances = cron.allow_multiple_instances == 1
    }

    private func save() async {
        isSaving = true
        errorText = nil
        defer { isSaving = false }

        let labels = labelsText
            .replacingOccurrences(of: "，", with: ",")
            .split(separator: ",")
            .map { $0.trimmed }
            .filter { !$0.isEmpty }

        let payload = CronPayload(
            id: target.cron?.id,
            name: name.trimmed,
            command: command.trimmed,
            schedule: schedule.trimmed,
            labels: Array(Set(labels)).sorted(),
            task_before: taskBefore.nilIfEmpty,
            task_after: taskAfter.nilIfEmpty,
            log_name: logName.nilIfEmpty,
            allow_multiple_instances: allowMultipleInstances ? 1 : 0,
            work_dir: workDir.nilIfEmpty,
            extra_schedules: target.cron?.extra_schedules
        )

        do {
            if target.isEdit {
                try await CronService.update(payload)
            } else {
                try await CronService.create(payload)
            }
            session.showToast(target.isEdit ? "任务已更新" : "任务已创建", tone: .success)
            presentationMode.wrappedValue.dismiss()
        } catch {
            errorText = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}

// MARK: - 定时规则模板

struct SchedulePreset: Identifiable, Hashable {
    let title: String
    let value: String

    var id: String { value }

    static let all: [SchedulePreset] = [
        SchedulePreset(title: "每分钟", value: "* * * * *"),
        SchedulePreset(title: "每 5 分钟", value: "*/5 * * * *"),
        SchedulePreset(title: "每 30 分钟", value: "*/30 * * * *"),
        SchedulePreset(title: "每小时", value: "0 * * * *"),
        SchedulePreset(title: "每天 0 点", value: "0 0 * * *"),
        SchedulePreset(title: "每天 8 点", value: "0 8 * * *"),
        SchedulePreset(title: "每周一 0 点", value: "0 0 * * 1"),
        SchedulePreset(title: "每月 1 号", value: "0 0 1 * *"),
        SchedulePreset(title: "仅一次", value: "@once"),
        SchedulePreset(title: "容器启动时", value: "@boot")
    ]
}
