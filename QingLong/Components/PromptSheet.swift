//
//  PromptSheet.swift
//  QingLong
//
//  统一的「输入一个值并确认」弹窗。用 sheet 实现，兼容 iOS 15 且行为一致。
//

import SwiftUI
import UIKit

struct PromptSheet: View {

    let title: String
    var message: String?
    var placeholder: String = ""
    @Binding var text: String
    var confirmTitle: String = "确定"
    var keyboardType: UIKeyboardType = .default
    var autocapitalize: Bool = false
    var isConfirmDisabled: Bool = false
    let onConfirm: () -> Void

    @Environment(\.presentationMode) private var presentationMode
    @FocusState private var focused: Bool

    var body: some View {
        NavigationView {
            Form {
                if let message {
                    Section {
                        Text(message)
                            .font(Theme.Font.callout)
                            .foregroundColor(Theme.textSecondary)
                    }
                }

                Section {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(autocapitalize ? .sentences : .never)
                        .autocorrectionDisabled(true)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(confirm)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(confirmTitle, action: confirm)
                        .font(.system(size: 16, weight: .semibold))
                        .disabled(text.trimmed.isEmpty || isConfirmDisabled)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true }
        }
    }

    private func confirm() {
        guard !text.trimmed.isEmpty else { return }
        onConfirm()
        presentationMode.wrappedValue.dismiss()
    }
}
