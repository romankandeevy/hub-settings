import AppKit
import Observation

/// Приложения набора: какие установлены и какие сейчас запущены. «Включено» в шапке модуля - это запущено ли
/// его приложение: включили - хаб его открывает, выключили - закрывает. Настройки и поведение приложений не меняются.
@MainActor
@Observable
final class AppMonitor {
    /// Установленное приложение набора.
    struct SuiteApp: Equatable {
        /// Идентификатор модуля: для приложений com.roman.<app> - это <app>, как папка в RomanSuite.
        let id: String
        let bundleID: String
        let name: String
    }

    private(set) var installed: [SuiteApp] = []
    private(set) var running: Set<String> = []
    private(set) var busy: Set<String> = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// Свои приложения набора подписаны как com.roman.<app>.
    private static let prefix = "com.roman."
    /// Сам хаб в списке модулей не нужен.
    private static let excluded: Set<String> = ["hub-settings"]
    /// Приложения набора с другим bundle id.
    private static let extra: [String: String] = ["flow": "com.flowlocal.mac"]

    init() {
        rescan()
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        // Поставили новое приложение - оно появится, когда вернёшься в окно хаба.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescan() }
        })
    }

    func bundleID(for app: String) -> String {
        installed.first { $0.id == app }?.bundleID ?? Self.extra[app] ?? Self.prefix + app
    }

    func isInstalled(_ app: String) -> Bool {
        running.contains(app) || NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID(for: app)) != nil
    }

    func isRunning(_ app: String) -> Bool { running.contains(app) }
    func isBusy(_ app: String) -> Bool { busy.contains(app) }

    func setRunning(_ app: String, _ on: Bool) {
        let id = bundleID(for: app)
        busy.insert(app)
        if on {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { busy.remove(app); return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, _ in
                Task { @MainActor in self?.busy.remove(app); self?.refresh() }
            }
        } else {
            NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
            // Ответ придёт уведомлением о закрытии; если приложение не закрылось, снимаем «занято» сами.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.busy.remove(app)
                self?.refresh()
            }
        }
    }

    /// Какой модуль у приложения с этим bundle id (nil - не из набора).
    private func appID(for bundleID: String) -> String? {
        if let known = installed.first(where: { $0.bundleID == bundleID }) { return known.id }
        if let extra = Self.extra.first(where: { $0.value == bundleID }) { return extra.key }
        guard bundleID.hasPrefix(Self.prefix) else { return nil }
        let id = String(bundleID.dropFirst(Self.prefix.count))
        return Self.excluded.contains(id) ? nil : id
    }

    private func refresh() {
        let now = Set(NSWorkspace.shared.runningApplications.compactMap { app -> String? in
            guard let id = app.bundleIdentifier, !app.isTerminated else { return nil }
            return appID(for: id)
        })
        // Дождались нужного состояния - переключатель больше не «занят».
        busy = busy.filter { now.contains($0) == running.contains($0) }
        if now != running { running = now }
    }

    /// Ищет приложения набора в /Applications и ~/Applications.
    private func rescan() {
        let folders = [URL(fileURLWithPath: "/Applications"),
                       FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var found: [String: SuiteApp] = [:]
        for folder in folders {
            let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for url in items where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { continue }
                let id: String
                if let extra = Self.extra.first(where: { $0.value == bundleID }) {
                    id = extra.key
                } else if bundleID.hasPrefix(Self.prefix) {
                    id = String(bundleID.dropFirst(Self.prefix.count))
                } else { continue }
                guard !Self.excluded.contains(id), found[id] == nil else { continue }
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                found[id] = SuiteApp(id: id, bundleID: bundleID, name: name)
            }
        }
        let list = found.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        if list != installed { installed = list }
    }
}
