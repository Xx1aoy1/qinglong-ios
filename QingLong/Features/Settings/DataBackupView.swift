//
//  DataBackupView.swift
//  QingLong
//
//  「数据备份」：导出 / 导入面板数据。
//  对应接口：PUT /api/system/data/export、PUT /api/system/data/import
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class DataBackupViewModel: ObservableObject {

    /// 可选导出项。`db` 与 `upload` 由后端固定包含，此处不列出。
    struct Option: Identifiable, Hashable {
        let id: String
        let title: String
        let detail: String
        var symbol: String

        static let all: [Option] = [
            Option(id: "config", title: "面板配置", detail: "面板设置、通知配置等 config 目录", symbol: "gearshape.fill"),
            Option(id: "scripts", title: "脚本目录", detail: "所有脚本文件（含随附的脚本历史）", symbol: "doc.text.fill"),
            Option(id: "log", title: "任务日志", detail: "定时任务与订阅的运行日志", symbol: "doc.plaintext.fill"),
            Option(id: "syslog", title: "面板系统日志", detail: "面板自身运行日志", symbol: "terminal.fill"),
            Option(id: "deps", title: "依赖记录", detail: "已安装的依赖与状态记录", symbol: "cube.box.fill"),
            Option(id: "dep_cache", title: "依赖缓存", detail: "下载的依赖包缓存，体积可能较大", symbol: "shippingbox.fill"),
            Option(id: "repo", title: "仓库缓存", detail: "订阅拉取的仓库缓存", symbol: "arrow.triangle.2.circlepath"),
            Option(id: "ssh.d", title: "SSH 配置", detail: "私有仓库使用的 SSH 密钥", symbol: "key.fill"),
            Option(id: "raw", title: "原始数据", detail: "data/raw 原始数据目录", symbol: "externaldrive.fill"),
            Option(id: "script-history", title: "脚本历史", detail: "脚本的历史版本快照", symbol: "clock.arrow.circlepath")
        ]
    }

    @Published var selected: Set<String> = ["config", "scripts", "log"]
    @Published var isExporting = false
    @Published var isImporting = false
    @Published var exportedSummary: String?
    @Published var lastError: String?

    private var exportURL: URL?

    func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    var selectedCount: Int { selected.count }

    // MARK: - 导出

    func export(session: AppSession) async {
        guard !isExporting else { return }
        isExporting = true
        lastError = nil
        defer { isExporting = false }

        let types = Array(selected).sorted()
        do {
            let data = try await SystemService.exportData(types: types)
            let stamp = Self.fileStampFormatter.string(from: Date())
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("qinglong-data-\(stamp).tgz")
            try data.write(to: url, options: .atomic)
            exportURL = url
            exportedSummary = "\(url.lastPathComponent) · \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
            session.showToast("导出成功", tone: .success)
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError.isUnauthorized {
                session.handle(error)
            } else {
                lastError = apiError.localizedDescription
                session.showToast("导出失败：\(apiError.localizedDescription)", tone: .danger)
            }
        }
    }

    var shareURL: URL? { exportURL }

    // MARK: - 导入

    func performImport(from url: URL, session: AppSession) async {
        guard !isImporting else { return }
        isImporting = true
        lastError = nil
        defer { isImporting = false }

        let needsRelease = url.startAccessingSecurityScopedResource()
        defer { if needsRelease { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                throw APIError.business(code: 0, message: "所选文件为空")
            }
            try await SystemService.importData(data, filename: url.lastPathComponent)
            session.showToast("导入成功，请重载面板以生效", tone: .success)
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError.isUnauthorized {
                session.handle(error)
            } else {
                lastError = apiError.localizedDescription
                session.showToast("导入失败：\(apiError.localizedDescription)", tone: .danger)
            }
        }
    }

    func reloadPanel(session: AppSession) async {
        do {
            try await SystemService.reload()
            session.showToast("已触发面板重载", tone: .success)
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError.isUnauthorized {
                session.handle(error)
            } else {
                session.showToast("重载失败：\(apiError.localizedDescription)", tone: .danger)
            }
        }
    }

    private static let fileStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

// MARK: - 页面

struct DataBackupView: View {

    @EnvironmentObject private var session: AppSession
    @StateObject private var model = DataBackupViewModel()

    @State private var showsExporter = false
    @State private var showsFileImporter = false
    @State private var showsReloadConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.large) {
                tipCard
                exportCard
                importCard
                if let error = model.lastError {
                    ErrorBanner(text: error)
                }
            }
            .padding(Theme.Spacing.large)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("数据备份")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsExporter) {
            ShareSheet(items: [model.shareURL].compactMap { $0 })
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: allowedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await model.performImport(from: url, session: session) }
            case .failure(let error):
                session.showToast("选择文件失败：\(error.localizedDescription)", tone: .danger)
            }
        }
        .alert(isPresented: $showsReloadConfirm) {
            Alert(
                title: Text("重载面板"),
                message: Text("导入数据后需要重载面板以使其生效。重载期间面板会短暂不可用，确定继续吗？"),
                primaryButton: .default(Text("重载")) {
                    Task { await model.reloadPanel(session: session) }
                },
                secondaryButton: .cancel(Text("稍后"))
            )
        }
    }

    private var allowedTypes: [UTType] {
        var types: [UTType] = [.data, .archive]
        if let tgz = UTType(filenameExtension: "tgz") { types.append(tgz) }
        if let gz = UTType(filenameExtension: "gz") { types.append(gz) }
        if let tar = UTType(filenameExtension: "tar") { types.append(tar) }
        return types
    }

    // MARK: - 说明

    private var tipCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(spacing: Theme.Spacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.warning)
                Text("备份说明")
                    .font(Theme.Font.callout.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
            }

            BulletLine("导出结果为 .tgz 压缩包，包含面板数据库与所选目录。")
            BulletLine("数据库（db）与上传目录（upload）始终会被包含。")
            BulletLine("导入会覆盖面板数据，操作不可撤销，请先做好备份。")
            BulletLine("导入完成后需要重载 / 重启面板才能生效。")
        }
        .qlCard()
    }

    // MARK: - 导出

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(title: "导出数据", subtitle: "选择需要一并打包的目录")

            VStack(spacing: 0) {
                ForEach(DataBackupViewModel.Option.all) { option in
                    optionRow(option)
                    if option.id != DataBackupViewModel.Option.all.last?.id {
                        Divider().background(Theme.separator)
                    }
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 0.6)
            )

            if let summary = model.exportedSummary {
                HStack(spacing: Theme.Spacing.small) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.success)
                    Text(summary)
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button("打开") { showsExporter = true }
                        .font(Theme.Font.caption.weight(.semibold))
                        .foregroundColor(Theme.brand)
                        .buttonStyle(.pressable)
                }
            }

            Button {
                Task { await model.export(session: session) }
            } label: {
                HStack(spacing: 6) {
                    if model.isExporting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.down.fill")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(model.isExporting ? "正在打包…" : "导出并保存（\(model.selectedCount) 项附加目录）")
                }
                .qlPrimaryButton(enabled: !model.isExporting)
            }
            .buttonStyle(.pressable)
            .disabled(model.isExporting)
        }
        .qlCard()
    }

    private func optionRow(_ option: DataBackupViewModel.Option) -> some View {
        Button {
            model.toggle(option.id)
        } label: {
            HStack(spacing: Theme.Spacing.medium) {
                Image(systemName: option.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.brand)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(Theme.Font.callout.weight(.medium))
                        .foregroundColor(Theme.textPrimary)
                    Text(option.detail)
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: model.selected.contains(option.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(model.selected.contains(option.id) ? Theme.brand : Theme.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    // MARK: - 导入

    private var importCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(title: "导入数据", subtitle: "从 .tgz 备份包恢复面板数据")

            HStack(spacing: Theme.Spacing.small) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.danger)
                Text("导入会覆盖面板现有数据，请确认备份包来源可靠。")
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                showsFileImporter = true
            } label: {
                HStack(spacing: 6) {
                    if model.isImporting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.brand))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.up.on.square.fill")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(model.isImporting ? "正在导入…" : "选择备份文件并导入")
                }
                .qlSecondaryButton()
            }
            .buttonStyle(.pressable)
            .disabled(model.isImporting)

            Button {
                showsReloadConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                    Text("重载面板使导入生效")
                }
                .font(Theme.Font.callout.weight(.semibold))
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.medium)
                .background(Theme.surfaceSunken)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .buttonStyle(.pressable)
        }
        .qlCard()
    }
}
