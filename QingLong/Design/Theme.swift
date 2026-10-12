//
//  Theme.swift
//  QingLong
//
//  设计令牌。全部颜色随浅色 / 深色模式自动切换。
//

import SwiftUI

enum Theme {

    // MARK: - 品牌色（青龙青）

    static let brand = Color.adaptive(light: "#0FA894", dark: "#2BD4BC")
    static let brandDeep = Color.adaptive(light: "#0B7F70", dark: "#12B7A8")
    static let brandSoft = Color.adaptive(light: "#E4F7F4", dark: "#10312D")

    static let brandGradient = LinearGradient(
        colors: [
            Color.adaptive(light: "#14C1A9", dark: "#2BD4BC"),
            Color.adaptive(light: "#0B8F9E", dark: "#0F7F96")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - 语义色

    static let success = Color.adaptive(light: "#12A24B", dark: "#3ED37A")
    static let warning = Color.adaptive(light: "#D98900", dark: "#FFB340")
    static let danger = Color.adaptive(light: "#D72C3F", dark: "#FF6B7A")
    static let info = Color.adaptive(light: "#1D6FE0", dark: "#5AA6FF")

    // MARK: - 背景与表面

    static let background = Color.adaptive(light: "#F2F4F7", dark: "#0E1115")
    static let surface = Color.adaptive(light: "#FFFFFF", dark: "#181D24")
    static let surfaceElevated = Color.adaptive(light: "#FFFFFF", dark: "#1F262F")
    static let surfaceSunken = Color.adaptive(light: "#F7F8FA", dark: "#141920")

    // MARK: - 文本

    static let textPrimary = Color.adaptive(light: "#14181F", dark: "#F2F5F8")
    static let textSecondary = Color.adaptive(light: "#6B7480", dark: "#9AA4B2")
    static let textTertiary = Color.adaptive(light: "#9BA3AE", dark: "#6B7683")

    // MARK: - 线条

    static let separator = Color.adaptive(light: "#E3E6EB", dark: "#282F38")
    static let stroke = Color.adaptive(light: "#E7EAEE", dark: "#2C343E")

    // MARK: - 排版

    enum Font {
        static let largeTitle = SwiftUI.Font.system(size: 30, weight: .bold)
        static let title = SwiftUI.Font.system(size: 22, weight: .semibold)
        static let headline = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 15, weight: .regular)
        static let callout = SwiftUI.Font.system(size: 14, weight: .regular)
        static let caption = SwiftUI.Font.system(size: 12, weight: .regular)
        static let mono = SwiftUI.Font.system(size: 13, design: .monospaced)
        static let monoSmall = SwiftUI.Font.system(size: 11.5, design: .monospaced)
    }

    // MARK: - 圆角与间距

    enum Radius {
        static let small: CGFloat = 8
        static let card: CGFloat = 14
        static let large: CGFloat = 20
        static let pill: CGFloat = 999
    }

    enum Spacing {
        static let tiny: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xlarge: CGFloat = 24
    }

    static let cardShadow = Color.black.opacity(0.05)
}
