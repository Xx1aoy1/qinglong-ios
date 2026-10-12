//
//  QingLongApp.swift
//  QingLong
//
//  青龙面板 iOS 客户端
//

import SwiftUI

@main
struct QingLongApp: App {

    @StateObject private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .tint(Theme.brand)
                .task {
                    await session.bootstrap()
                }
        }
    }
}
