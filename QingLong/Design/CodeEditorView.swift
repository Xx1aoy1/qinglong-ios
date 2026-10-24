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
/// 坑一：SwiftUI 的 `TextEditor` 绑定的字符串每敲一个字符都会变一次，父视图随即重算，
/// SwiftUI 会把整段文本重新写回底层 `UITextView`，`selectedRange` / `contentOffset`
/// 一起被重置 —— 表现就是「删一个字，光标跳到别处」。
///
/// 坑二（更隐蔽）：即便自己包 `UITextView`，只要在 `updateUIView` 里每次更新都重设
/// `textColor` / `font` / `isEditable` / `textContainerInset`，`UITextView` 也会重建
/// 文本属性并把 `selectedRange` 顶到末尾 —— 依旧跳。所以这里**只在真的变了的时候**
/// 才动外观（仅深浅色切换 / 配置变化），普通输入路径一个 setter 都不碰。
struct CodeEditorView: UIViewRepresentable {

    @Binding var text: String

    var fontSize: CGFloat = 13
    var isEditable: Bool = true
    /// 文本四周留白，代替 `TextEditor` 外层的 padding
    var insets: UIEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 14, right: 10)

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator

        view.text = text
        view.textContainer.lineFragmentPadding = 0
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive

        // 写配置 / 脚本最怕被「智能」改写
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no

        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        context.coordinator.applyAppearance(
            to: view,
            scheme: colorScheme,
            fontSize: fontSize,
            isEditable: isEditable,
            insets: insets
        )
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        // 外观只在真的变了时才改（深浅色切换、配置变化）。
        // 每次更新都设一遍 textColor / isEditable 会把光标位置冲掉。
        if coordinator.appliedScheme != colorScheme
            || coordinator.appliedEditable != isEditable
            || coordinator.appliedFontSize != fontSize
            || coordinator.appliedInsets != insets {
            coordinator.applyAppearance(
                to: view,
                scheme: colorScheme,
                fontSize: fontSize,
                isEditable: isEditable,
                insets: insets
            )
        }

        // 拼音等输入法正在组词（markedText）时不要动文本，否则候选会被打断
        if view.markedTextRange != nil { return }

        // 用户打字触发的回写：底层文本已经是这份内容，立即返回，光标一动都不动
        guard view.text != text else { return }

        // 走到这里说明内容是被外部改掉的（首次加载 / 重新读取）
        let caret = min(view.selectedRange.location, (text as NSString).length)
        view.text = text
        view.selectedRange = NSRange(location: caret, length: 0)
    }

    final class Coordinator: NSObject, UITextViewDelegate {

        var parent: CodeEditorView

        var appliedScheme: ColorScheme?
        var appliedEditable: Bool?
        var appliedFontSize: CGFloat?
        var appliedInsets: UIEdgeInsets?

        init(_ parent: CodeEditorView) { self.parent = parent }

        func applyAppearance(
            to view: UITextView,
            scheme: ColorScheme,
            fontSize: CGFloat,
            isEditable: Bool,
            insets: UIEdgeInsets
        ) {
            appliedScheme = scheme
            appliedEditable = isEditable
            appliedFontSize = fontSize
            appliedInsets = insets

            // 这些 setter 会重建文本属性、顺带把 selectedRange 顶到末尾，
            // 所以改完外观把光标按原样放回去。
            let selected = view.selectedRange

            view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            view.textColor = UIColor(Theme.textPrimary)
            view.backgroundColor = UIColor(Theme.surfaceSunken)
            view.tintColor = UIColor(Theme.brand)
            view.textContainerInset = insets
            view.isEditable = isEditable

            let length = (view.text as NSString).length
            view.selectedRange = NSRange(location: min(selected.location, length), length: 0)
        }

        func textViewDidChange(_ textView: UITextView) {
            // 只把内容回写给绑定，不去碰 textView 自身
            guard parent.text != textView.text else { return }
            parent.text = textView.text
        }
    }
}
