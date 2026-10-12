//
//  ViewModifiers.swift
//  QingLong
//

import SwiftUI

// MARK: - 卡片容器

struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.Spacing.large
    var elevated: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(elevated ? Theme.surfaceElevated : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 0.6)
            )
    }
}

extension View {
    func qlCard(padding: CGFloat = Theme.Spacing.large, elevated: Bool = true) -> some View {
        modifier(CardModifier(padding: padding, elevated: elevated))
    }

    /// 屏幕背景
    func qlScreenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }

    /// 主按钮样式（渐变背景 + 白色文字）
    func qlPrimaryButton(enabled: Bool = true) -> some View {
        self
            .font(Theme.Font.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                Group {
                    if enabled {
                        Theme.brandGradient
                    } else {
                        Color.gray.opacity(0.35)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// 次要按钮样式
    func qlSecondaryButton() -> some View {
        self
            .font(Theme.Font.headline)
            .foregroundColor(Theme.brand)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Theme.brandSoft)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// 条件修饰
    @ViewBuilder
    func `if`<Transformed: View>(
        _ condition: Bool,
        transform: (Self) -> Transformed
    ) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - 按压反馈

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}
