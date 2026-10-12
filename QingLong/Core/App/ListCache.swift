//
//  ListCache.swift
//  QingLong
//
//  列表数据的进程内缓存。
//
//  背景
//  ----
//  TabView 在切换 / 重建页面时会重新创建 ViewModel，导致每次进入列表页都要
//  重新请求并长时间停留在 loading。这里把最近一次成功加载的结果缓存下来，
//  ViewModel 初始化时先同步命中缓存（立即可见），再在后台静默刷新。
//
//  缓存只在内存中，切换服务器或退出登录时由 AppSession 清空。
//

import Foundation

enum ListCache {

    private static let lock = NSLock()

    private static var _crons: [QLCron] = []
    private static var _envs: [QLEnv] = []
    private static var _subscriptions: [QLSubscription] = []
    private static var _dependences: [QLDependence] = []

    // MARK: - 写入

    static func store(crons: [QLCron]) { lock.lock(); _crons = crons; lock.unlock() }
    static func store(envs: [QLEnv]) { lock.lock(); _envs = envs; lock.unlock() }
    static func store(subscriptions: [QLSubscription]) {
        lock.lock(); _subscriptions = subscriptions; lock.unlock()
    }
    static func store(dependences: [QLDependence]) {
        lock.lock(); _dependences = dependences; lock.unlock()
    }

    // MARK: - 读取

    static var crons: [QLCron] { lock.lock(); defer { lock.unlock() }; return _crons }
    static var envs: [QLEnv] { lock.lock(); defer { lock.unlock() }; return _envs }
    static var subscriptions: [QLSubscription] {
        lock.lock(); defer { lock.unlock() }; return _subscriptions
    }
    static var dependences: [QLDependence] {
        lock.lock(); defer { lock.unlock() }; return _dependences
    }

    // MARK: - 清空

    static func clear() {
        lock.lock()
        _crons = []
        _envs = []
        _subscriptions = []
        _dependences = []
        lock.unlock()
    }
}
