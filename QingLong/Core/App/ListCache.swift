//
//  ListCache.swift
//  QingLong
//
//  列表数据缓存（内存 + 磁盘）。
//
//  为什么需要它
//  ------------
//  1. TabView 重建页面时会重新创建 ViewModel，于是每次进入列表页都要重新请求，
//     并长时间停留在 loading 状态；
//  2. `/api/dependencies` 在面板侧非常重：后端会把**每条依赖的完整安装日志**一起
//     返回（`DependenceModel.findAll()` 含 `log` JSON 列），并且每次请求都要逐条
//     执行 shell 命令探测安装状态（`refreshInstalledStatuses`），
//     所以一次请求往往要好几秒甚至更久。
//
//  因此把最近一次成功加载的结果缓存下来：
//  - 内存缓存：同一进程内切 Tab / 重进页面立刻可见；
//  - 磁盘缓存：App 冷启动后第一次进入列表页也能立刻看到内容，而不是白屏等请求。
//
//  磁盘文件写在 Caches 目录（系统可回收，不是用户数据），
//  切换服务器 / 退出登录时由 AppSession 清空。
//

import Foundation

enum ListCache {

    enum Key: String, CaseIterable {
        case crons, envs, subscriptions, dependences
    }

    // MARK: - 内部存储

    private static let lock = NSLock()
    private static let ioQueue = DispatchQueue(label: "com.qinglong.listcache.io", qos: .utility)

    private static var _crons: [QLCron] = []
    private static var _envs: [QLEnv] = []
    private static var _subscriptions: [QLSubscription] = []
    private static var _dependences: [QLDependence] = []
    private static var _stamps: [Key: Date] = [:]
    private static var _diskLoaded = false

    /// 落盘载体：数据 + 写入时间
    private struct DiskBox<T: Codable>: Codable {
        var savedAt: Double
        var items: [T]
    }

    // MARK: - 写入

    static func store(crons: [QLCron], at date: Date = Date()) {
        lock.lock(); _crons = crons; _stamps[.crons] = date; lock.unlock()
        persist(crons, key: .crons, at: date)
    }

    static func store(envs: [QLEnv], at date: Date = Date()) {
        lock.lock(); _envs = envs; _stamps[.envs] = date; lock.unlock()
        persist(envs, key: .envs, at: date)
    }

    static func store(subscriptions: [QLSubscription], at date: Date = Date()) {
        lock.lock(); _subscriptions = subscriptions; _stamps[.subscriptions] = date; lock.unlock()
        persist(subscriptions, key: .subscriptions, at: date)
    }

    static func store(dependences: [QLDependence], at date: Date = Date()) {
        lock.lock(); _dependences = dependences; _stamps[.dependences] = date; lock.unlock()
        // 安装日志可能极大（单条依赖的日志就能到 MB 级），列表页并不需要它，
        // 落盘前先剥掉，避免磁盘缓存膨胀成几十 MB。
        var slim = dependences
        for index in slim.indices where slim[index].log != nil {
            slim[index].log = nil
        }
        persist(slim, key: .dependences, at: date)
    }

    // MARK: - 读取

    static var crons: [QLCron] {
        loadFromDiskIfNeeded()
        lock.lock(); defer { lock.unlock() }
        return _crons
    }

    static var envs: [QLEnv] {
        loadFromDiskIfNeeded()
        lock.lock(); defer { lock.unlock() }
        return _envs
    }

    static var subscriptions: [QLSubscription] {
        loadFromDiskIfNeeded()
        lock.lock(); defer { lock.unlock() }
        return _subscriptions
    }

    static var dependences: [QLDependence] {
        loadFromDiskIfNeeded()
        lock.lock(); defer { lock.unlock() }
        return _dependences
    }

    /// 该列表最近一次成功加载的时间（内存缓存命中时用来判断是否过期）
    static func lastLoaded(_ key: Key) -> Date? {
        loadFromDiskIfNeeded()
        lock.lock(); defer { lock.unlock() }
        return _stamps[key]
    }

    // MARK: - 清空

    static func clear() {
        lock.lock()
        _crons = []
        _envs = []
        _subscriptions = []
        _dependences = []
        _stamps = [:]
        lock.unlock()

        ioQueue.async {
            guard let dir = directory else { return }
            for key in Key.allCases {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(key.rawValue).json"))
            }
        }
    }

    // MARK: - 磁盘

    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("QLListCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func fileURL(_ key: Key) -> URL? {
        directory?.appendingPathComponent("\(key.rawValue).json")
    }

    private static func persist<T: Codable>(_ items: [T], key: Key, at date: Date) {
        guard let target = fileURL(key) else { return }
        let box = DiskBox(savedAt: date.timeIntervalSince1970, items: items)
        ioQueue.async {
            guard let data = try? JSONEncoder().encode(box) else { return }
            try? data.write(to: target, options: .atomic)
        }
    }

    /// 首次读取时把磁盘缓存灌进内存。只做一次，之后走内存。
    private static func loadFromDiskIfNeeded() {
        lock.lock()
        if _diskLoaded {
            lock.unlock()
            return
        }
        _diskLoaded = true
        lock.unlock()

        guard let dir = directory else { return }

        func read<T: Codable>(_ key: Key, _ type: T.Type) -> DiskBox<T>? {
            let file = dir.appendingPathComponent("\(key.rawValue).json")
            guard let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
            return try? JSONDecoder().decode(DiskBox<T>.self, from: data)
        }

        let crons = read(.crons, QLCron.self)
        let envs = read(.envs, QLEnv.self)
        let subs = read(.subscriptions, QLSubscription.self)
        let deps = read(.dependences, QLDependence.self)

        lock.lock()
        if _crons.isEmpty, let value = crons { _crons = value.items }
        if _envs.isEmpty, let value = envs { _envs = value.items }
        if _subscriptions.isEmpty, let value = subs { _subscriptions = value.items }
        if _dependences.isEmpty, let value = deps { _dependences = value.items }
        let saved: [(Key, Double?)] = [
            (.crons, crons?.savedAt),
            (.envs, envs?.savedAt),
            (.subscriptions, subs?.savedAt),
            (.dependences, deps?.savedAt),
        ]
        for (key, time) in saved {
            guard let time else { continue }
            if _stamps[key] == nil {
                _stamps[key] = Date(timeIntervalSince1970: time)
            }
        }
        lock.unlock()
    }
}
