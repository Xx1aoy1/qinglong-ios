//
//  MainTabView.swift
//  QingLong
//
//  登录后的主界面：概览 / 任务 / 变量 / 更多
//

import SwiftUI

struct MainTabView: View {

    @EnvironmentObject private var session: AppSession
    @State private var selection: Tab = .dashboard

    enum Tab: Hashable {
        case dashboard, crons, envs, more
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationView { DashboardView() }
                .navigationViewStyle(.stack)
                .tabItem {
                    Label("概览", systemImage: "square.grid.2x2.fill")
                }
                .tag(Tab.dashboard)

            NavigationView { CronListView() }
                .navigationViewStyle(.stack)
                .tabItem {
                    Label("任务", systemImage: "clock.fill")
                }
                .tag(Tab.crons)

            NavigationView { EnvListView() }
                .navigationViewStyle(.stack)
                .tabItem {
                    Label("变量", systemImage: "shippingbox.fill")
                }
                .tag(Tab.envs)

            NavigationView { MoreView() }
                .navigationViewStyle(.stack)
                .tabItem {
                    Label("更多", systemImage: "ellipsis.circle.fill")
                }
                .tag(Tab.more)
        }
        .accentColor(Theme.brand)
    }
}
