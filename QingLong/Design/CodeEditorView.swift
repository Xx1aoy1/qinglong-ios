//
//  CodeEditorView.swift
//  QingLong
//
//  代码 / 配置文本编辑器（脚本、config.sh 等）。
//

import SwiftUI
import UIKit

/// 等宽文本编辑器。
///
/// 为什么不用 SwiftUI 的 `TextEditor`：
/// 它绑定的字符串每敲一个字符都会变一次，父视图随即重算，SwiftUI 会把整段文本重新写回
/// 底层的 `UITextView`，`selectedRange` / `contentOffset` 被一起重置 —— 表现就是
/// 「删掉一个字符，光标和视图突然跳到别处，找不回刚才的位置」，文本越长越明显。
///
/// 这里直接包一层 `UITextView`：只有「外部内容确实变了」（首次加载、重新读取）才整体替换
/// 文本；用户自己打字触发的回写会因为 `view.text == text` 直接短路，光标一动不动。
struct CodeEditorView: UIViewRepresentable {

    @Binding var text: String

    var fontSize: CGFloat = 13
    var isEditable: Bool = true
    /// 文本四周留白，代替 `TextEditor` 外层的 padding
    var insets: UIEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 14, right: 10)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator

        view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.text = text
        view.backgroundColor = UIColor(Theme.surfaceSunken)
        view.textColor = UIColor(Theme.textPrimary)
        view.tintColor = UIColor(Theme.brand)

        view.textContainerInset = insets
        view.textContainer.lineFragmentPadding = 0
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive

        // 写配置/脚本最怕被「智能」改写
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no

        view.isEditable = isEditable
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self

        view.backgroundColor = UIColor(Theme.surfaceSunken)
        view.textColor = UIColor(Theme.textPrimary)
        view.tintColor = UIColor(Theme.brand)
        view.isEditable = isEditable
        if view.font?.pointSize != fontSize {
            view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        if view.textContainerInset != insets {
            view.textContainerInset = insets
        }

        // 拼音等输入法正在组词（markedText）时不要动文本，否则候选会被打断
        if view.markedTextRange != nil { return }

        // 用户打字触发的回写：底层文本已经是这份内容，立即返回，光标不会被重置
        guard view.text != text else { return }

        // 走到这里说明内容是被外部改掉的（首次加载 / 重新读取 / 载入草稿）
        let length = (text as NSString).length
        let caret = min(view.selectedRange.location, length)
        view.text = text
        view.selectedRange = NSRange(location: caret, length: 0)
    }

    final class Coordinator: NSObject, UITextViewDelegate {

        var parent: CodeEditorView

        init(_ parent: CodeEditorView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            // 只把内容回写给绑定，不去碰 textView 自身
            guard parent.text != textView.text else { return }
            parent.text = textView.text
        }
    }
}
