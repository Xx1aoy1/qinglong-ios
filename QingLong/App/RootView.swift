//
//  RootView.swift
//  QingLong
//
//  根据会话状态切换顶层界面。
//

import SwiftUI

struct RootView: View {

    @EnvironmentObject private var session: AppSession

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch session.phase {
            case .booting:
                SplashView()
                    .transition(.opacity)

            case .needsServer:
                ServerListView(mode: .onboarding)
                    .transition(.opacity)

            case .needsLogin:
                LoginView()
                    .transition(.opacity)

            case .ready:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.phase)
        .overlay(ToastOverlay(message: session.toast))
    }
}

/// 启动页
struct SplashView: View {
    @State private var animate = false

    var body: some View {
        VStack(spacing: Theme.Spacing.large) {
            BrandLogo(size: 84)
                .scaleEffect(animate ? 1 : 0.9)
                .opacity(animate ? 1 : 0)

            VStack(spacing: 6) {
                Text(AppInfo.displayName)
                    .font(Theme.Font.title)
                    .foregroundColor(Theme.textPrimary)

                Text("正在连接青龙面板…")
                    .font(Theme.Font.callout)
                    .foregroundColor(Theme.textSecondary)
            }
            .opacity(animate ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { animate = true }
        }
    }
}
