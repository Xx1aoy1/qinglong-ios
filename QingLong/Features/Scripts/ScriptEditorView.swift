//
//  ScriptEditorView.swift
//  QingLong
//
//  脚本编辑器：加载 / 编辑 / 保存 / 运行。
//

import SwiftUI
import UIKit

@MainActor
final class ScriptEditorViewModel: ObservableObject {

    /// 编辑框文本。**故意不用 @Published**：每敲一个字符都发通知会让整页重算、编辑区被
    /// 重新布局，光标容易跑。只有「是否已修改 / 字符数」真的变了才通知 UI。
    private(set) var content = ""
    private(set) var original = ""

    @Published var state: LoadState = .idle
    @Published var isSaving = false
    @Published var isRunning = false
    @Published var runOutput: String = ""
    @Published var showsOutput = false
    @Published private(set) var isDirty = false
    @Published private(set) var charCount = 0

    private var countTask: Task<Void, Never>?

    var hasChanges: Bool { content != original }

    /// 给编辑器用的绑定：写入绕开 @Published，不惊动整页刷新
    var textBinding: Binding<String> {
        Binding(
            get: { [weak self] in self?.content ?? "" },
            set: { [weak self] in self?.updateContent($0) }
        )
    }

    /// 编辑器每次输入都会走这里
    func updateContent(_ new: String) {
        guard new != content else { return }
        content = new

        // 脏标记只在 false/true 翻转时通知一次，连续输入不再重算页面
        let dirty = hasChanges
        if isDirty != dirty { isDirty = dirty }

        scheduleCountRefresh()
    }

    /// 字符数不必每个按键都算（`String.count` 是 O(n)），攒一下再刷
    private func scheduleCountRefresh() {
        countTask?.cancel()
        countTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 220_000_000) } catch { return }
            guard let self = self else { return }
            let count = self.content.count
            if self.charCount != count { self.charCount = count }
        }
    }

    /// 已加载成功的文件标识。用来挡住重复拉取 —— 重复拉取会把编辑框里的内容顶回服务器版本。
    private var loadedKey: String?

    func load(path: String, file: String, session: AppSession, force: Bool = false) async {
        let key = "\(path)/\(file)"
        if !force, loadedKey == key, case .loaded = state { return }
        state = .loading
        do {
            let text = try await ScriptService.content(path: path, file: file)
            content = text
            original = text
            charCount = text.count
            if isDirty { isDirty = false }
            loadedKey = key
            state = .loaded
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if apiError == .cancelled { return }
            if apiError.isUnauthorized { session.handle(error); return }
            state = .failed(apiError.localizedDescription)
        }
    }

    func save(path: String, file: String, session: AppSession) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await ScriptService.save(filename: file, path: path, content: content, create: false)
            original = content
            if isDirty { isDirty = false }
            session.showToast("已保存", tone: .success)
        } catch {
            session.handle(error)
        }
    }

    func run(path: String, file: String, session: AppSession) async {
        isRunning = true
        runOutput = ""
        showsOutput = true
        defer { isRunning = false }
        do {
            // 先保存，再执行，避免运行旧内容
            if hasChanges {
                try await ScriptService.save(filename: file, path: path, content: content, create: false)
                original = content
                if isDirty { isDirty = false }
            }
            _ = try await ScriptService.run(filename: file, path: path, content: content)
            runOutput = "已提交执行请求，可在「日志」中查看输出。"
            session.showToast("已触发运行", tone: .success)
        } catch {
            runOutput = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            session.handle(error)
        }
    }

    func stop(path: String, file: String, session: AppSession) async {
        do {
            try await ScriptService.stop(filename: file, path: path)
            session.showToast("已发送停止指令", tone: .warning)
        } catch {
            session.handle(error)
        }
    }
}

struct ScriptEditorView: View {

    let file: QLFileItem

    @EnvironmentObject private var session: AppSession
    @StateObject private var viewModel = ScriptEditorViewModel()

    @State private var showsDelete = false
    @State private var showsRename = false
    @State private var renameDraft = ""
    @State private var shareItem: ShareItem?

    init(file: QLFileItem) {
        self.file = file
    }

    private var parentPath: String {
        var value = file.parent ?? ""
        while value.hasPrefix("/") { value.removeFirst() }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                LoadingView(text: "读取脚本内容…")
            case .failed(let message):
                ScrollView {
                    EmptyStateView(
                        symbol: "doc.questionmark",
                        title: "无法读取脚本",
                        message: message,
                        actionTitle: "重试"
                    ) { Task { await load() } }
                }
            default:
                editor
            }
        }
        .background(Theme.surfaceSunken.ignoresSafeArea())
        .navigationTitle(file.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: Theme.Spacing.small) {
                    Button {
                        Task { await viewModel.run(path: parentPath, file: file.title, session: session) }
                    } label: {
                        if viewModel.isRunning {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "play.fill").font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .disabled(viewModel.isRunning)

                    Button {
                        Task { await viewModel.save(path: parentPath, file: file.title, session: session) }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text(viewModel.isDirty ? "保存*" : "保存")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .disabled(viewModel.isSaving || !viewModel.isDirty)

                    Menu {
                        Button {
                            UIPasteboard.general.string = viewModel.content
                            session.showToast("已复制脚本内容", tone: .success)
                        } label: { Label("复制内容", systemImage: "doc.on.doc") }

                        Button {
                            Task { await download() }
                        } label: { Label("下载到「文件」", systemImage: "square.and.arrow.down") }

                        Divider()

                        Button {
                            renameDraft = file.title
                            showsRename = true
                        } label: { Label("重命名", systemImage: "pencil") }

                        Button {
                            Task { await viewModel.stop(path: parentPath, file: file.title, session: session) }
                        } label: { Label("停止运行", systemImage: "stop.circle") }

                        Divider()

                        Button(role: .destructive) {
                            showsDelete = true
                        } label: { Label("删除文件", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 15, weight: .semibold))
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showsOutput) {
            NavigationView {
                ScrollView {
                    Text(viewModel.runOutput.isEmpty ? "（暂无输出）" : viewModel.runOutput)
                        .font(Theme.Font.mono)
                        .foregroundColor(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.medium)
                        .textSelection(.enabled)
                }
                .background(Theme.surfaceSunken.ignoresSafeArea())
                .navigationTitle("运行结果")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("完成") { viewModel.showsOutput = false }
                    }
                }
            }
            .navigationViewStyle(.stack)
        }
        .sheet(isPresented: $showsRename) {
            PromptSheet(title: "重命名", placeholder: "新的文件名", text: $renameDraft) {
                Task { await rename() }
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .alert("删除文件", isPresented: $showsDelete) {
            Button("删除", role: .destructive) { Task { await remove() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定删除「\(file.title)」吗？该操作不可撤销。")
        }
        .task { await load() }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.small) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                Text(file.key)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if viewModel.isDirty {
                    StatusPill(text: "未保存", tone: .warning, symbol: "circle.fill", compact: true)
                }
                Text("\(viewModel.charCount) 字符")
                    .font(Theme.Font.caption)
                    .monospacedDigit()
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, 7)
            .background(Theme.surface)

            Divider().background(Theme.separator)

            // 同 ConfigFilesView：换成 UITextView 包装的编辑器，避免删字时光标跳走
            CodeEditorView(text: viewModel.textBinding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() async {
        await viewModel.load(path: parentPath, file: file.title, session: session)
    }

    private func rename() async {
        let newName = renameDraft.trimmed
        guard !newName.isEmpty, newName != file.title else { return }
        do {
            try await ScriptService.rename(path: parentPath, filename: file.title, newFilename: newName)
            session.showToast("已重命名，请返回列表刷新", tone: .success)
        } catch {
            session.handle(error)
        }
    }

    private func remove() async {
        do {
            try await ScriptService.remove(path: parentPath, filename: file.title)
            session.showToast("已删除", tone: .success)
        } catch {
            session.handle(error)
        }
    }

    private func download() async {
        do {
            let data = try await ScriptService.download(path: parentPath, filename: file.title)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.title)
            try data.write(to: url)
            shareItem = ShareItem(url: url)
        } catch {
            session.handle(error)
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
