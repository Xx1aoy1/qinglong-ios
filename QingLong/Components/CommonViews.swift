//
//  CommonViews.swift
//  QingLong
//
//  通用小组件集合。
//

import SwiftUI

// MARK: - 加载状态

enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    var isLoading: Bool { self == .loading }
    var errorText: String? {
        if case .failed(let text) = self { return text }
        return nil
    }
}

// MARK: - 品牌标识

struct BrandLogo: View {
    var size: CGFloat = 64
    var showShadow: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Theme.brandGradient)
                .frame(width: size, height: size)
                .shadow(
                    color: showShadow ? Theme.brand.opacity(0.3) : .clear,
                    radius: size * 0.16,
                    x: 0,
                    y: size * 0.08
                )

            Image(systemName: "bolt.horizontal.fill")
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    var symbol: String = "tray"
    var title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.medium) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundColor(Theme.textTertiary)
                .padding(.bottom, 2)

            Text(title)
                .font(Theme.Font.headline)
                .foregroundColor(Theme.textPrimary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(Theme.Font.callout)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xlarge)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(Theme.Font.callout.weight(.semibold))
                    .foregroundColor(Theme.brand)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - 加载指示

struct LoadingView: View {
    var text: String = "加载中…"

    var body: some View {
        VStack(spacing: Theme.Spacing.medium) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Theme.brand))
            Text(text)
                .font(Theme.Font.callout)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

/// 半透明遮罩 + 菊花（用于阻塞式操作）
struct BlockingOverlay: View {
    var text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(spacing: Theme.Spacing.medium) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.brand))
                Text(text)
                    .font(Theme.Font.callout)
                    .foregroundColor(Theme.textPrimary)
            }
            .padding(Theme.Spacing.xlarge)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .shadow(color: Theme.cardShadow, radius: 20, y: 8)
        }
    }
}

// MARK: - 错误横幅

struct ErrorBanner: View {
    let text: String
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.danger)
                .font(.system(size: 14))

            Text(text)
                .font(Theme.Font.callout)
                .foregroundColor(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let onRetry {
                Button("重试", action: onRetry)
                    .font(Theme.Font.caption.weight(.semibold))
                    .foregroundColor(Theme.brand)
            }
        }
        .padding(Theme.Spacing.medium)
        .background(Theme.danger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .padding(.horizontal, Theme.Spacing.large)
    }
}

// MARK: - 信息行

struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.textPrimary
    var mono: Bool = false
    var copyable: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.medium) {
            Text(label)
                .font(Theme.Font.callout)
                .foregroundColor(Theme.textSecondary)
                .frame(width: 92, alignment: .leading)

            Text(value.isEmpty ? "—" : value)
                .font(mono ? Theme.Font.mono : Theme.Font.callout)
                .foregroundColor(valueColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - 分组标题

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .textCase(nil)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 要点行

/// 说明性要点行：前置图标 + 文案，左对齐自动换行。
struct BulletLine: View {
    let text: String
    var symbol: String = "checkmark.circle.fill"
    var tint: Color = Theme.brand

    init(_ text: String, symbol: String = "checkmark.circle.fill", tint: Color = Theme.brand) {
        self.text = text
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.small) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundColor(tint)
            Text(text)
                .font(Theme.Font.callout)
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Toast

struct ToastOverlay: View {
    let message: ToastMessage?

    var body: some View {
        VStack {
            if let message {
                HStack(spacing: Theme.Spacing.small) {
                    Image(systemName: message.tone.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(message.tone.color)
                    Text(message.text)
                        .font(Theme.Font.callout)
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, Theme.Spacing.large)
                .padding(.vertical, Theme.Spacing.medium)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(message.tone.color.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: Theme.cardShadow, radius: 16, y: 6)
                .padding(.horizontal, Theme.Spacing.large)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(message.id)
            }
            Spacer()
        }
        .padding(.top, Theme.Spacing.small)
        .allowsHitTesting(false)
    }
}

// MARK: - 工具条按钮

struct CircleToolbarButton: View {
    let symbol: String
    var tint: Color = Theme.brand
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.pressable)
    }
}
