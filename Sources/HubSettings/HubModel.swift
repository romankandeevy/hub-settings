import AppKit
import Observation
import SuiteKit

/// Одно значение настройки, за которым следит SwiftUI. Строка формы читает только свою ячейку,
/// поэтому правка одного поля перерисовывает одну строку, а не все сотни строк модуля.
@MainActor
@Observable
final class ValueCell {
    var value: SuiteValue?
    init(_ value: SuiteValue?) { self.value = value }
}

/// Счётчик правок приложения: его читают те, кому нужен весь файл сразу (превью, «Сбросить»).
@MainActor
@Observable
final class RevisionCell {
    var count = 0
}

/// Все приложения набора, которые опубликовали схему настроек, и их текущие значения.
/// Хаб правит `settings.json` через `SuiteStore`: приложение подхватывает изменение сразу,
/// а если файл поменяли снаружи (само приложение или руками), хаб тоже это видит.
@MainActor
@Observable
final class HubModel {
    private(set) var schemas: [SuiteSchema] = [] {
        didSet { fieldIndex = Dictionary(schemas.map { ($0.app, Self.index($0)) }, uniquingKeysWith: { a, _ in a }) }
    }
    /// Значения файлов настроек. Сами по себе не наблюдаются: вьюхи читают ячейки (`ValueCell`, `RevisionCell`).
    @ObservationIgnored private var values: [String: [String: SuiteValue]] = [:]
    @ObservationIgnored private var cells: [String: [String: ValueCell]] = [:]
    @ObservationIgnored private var revisions: [String: RevisionCell] = [:]
    /// Поля схем по ключу: поиск поля по ключу - на каждой строке и ручке превью, линейный перебор 300 полей дорог.
    @ObservationIgnored private var fieldIndex: [String: [String: SuiteSchema.Field]] = [:]
    var selection: String? {
        didSet { UserDefaults.standard.set(selection, forKey: "selection") }
    }

    @ObservationIgnored private var stores: [String: any SettingsStore] = [:]
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var showObserver: NSObjectProtocol?

    /// Приложение набора просит открыть свой модуль (⌘, во Flow): объект уведомления - id модуля.
    static let showModule = Notification.Name("com.roman.suite.hub.show")

    init() {
        selection = UserDefaults.standard.string(forKey: "selection")
        reload()
        // Новое приложение или новая версия схемы появляются, когда возвращаешься в окно хаба.
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        showObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.showModule, object: nil, queue: .main
        ) { [weak self] note in
            // «island» - модуль, «island#page:island.page.music» - сразу его подстраница или строка.
            let parts = (note.object as? String)?.split(separator: "#", maxSplits: 1).map(String.init) ?? []
            MainActor.assumeIsolated {
                self?.reload()
                if let module = parts.first { self?.selection = module }
                if parts.count > 1 { self?.pendingTarget = parts[1] }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    var selected: SuiteSchema? {
        schemas.first { $0.app == selection } ?? schemas.first
    }

    func reload() {
        let published = SuiteSchema.installed()
        // Приложения, которые хранят настройки в своих UserDefaults: их схему хаб знает сам.
        let external = ExternalSettings.installed.filter { item in !published.contains { $0.app == item.schema.app } }
        let fresh = (published + external.map(\.schema))
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        if fresh != schemas { schemas = fresh }
        for schema in published where stores[schema.app] == nil {
            let store = SuiteStore(app: schema.app, name: schema.file, default: schema.defaults)
            store.onChange = { [weak self] value in self?.ingest(schema.app, value) }
            stores[schema.app] = store
            ingest(schema.app, store.value)
        }
        for item in external {
            let app = item.schema.app
            if let store = stores[app] as? DefaultsStore {
                store.refresh()
                continue
            }
            let store = DefaultsStore(item)
            store.onChange = { [weak self] value in self?.ingest(app, value) }
            stores[app] = store
            ingest(app, store.value)
        }
    }

    /// Новый файл настроек приложения: меняются только ячейки, чьё значение стало другим.
    private func ingest(_ app: String, _ value: [String: SuiteValue]) {
        guard values[app] != value else { return }
        values[app] = value
        for (key, cell) in cells[app] ?? [:] {
            let fresh = SettingsPath.get(value, key)
            if cell.value != fresh { cell.value = fresh }
        }
        revision(app).count += 1
    }

    private func cell(_ app: String, _ key: String) -> ValueCell {
        if let cell = cells[app]?[key] { return cell }
        let cell = ValueCell(values[app].flatMap { SettingsPath.get($0, key) })
        cells[app, default: [:]][key] = cell
        return cell
    }

    private func revision(_ app: String) -> RevisionCell {
        if let cell = revisions[app] { return cell }
        let cell = RevisionCell()
        revisions[app] = cell
        return cell
    }

    /// Ключ может быть вложенным через точку: «moduleOptions.weather.hours» - это
    /// `moduleOptions` → `weather` → `hours` в файле настроек.
    func value(_ app: String, _ key: String) -> SuiteValue? {
        cell(app, key).value ?? defaults(app)?[key]
    }

    private func defaults(_ app: String) -> [String: SuiteValue]? {
        schemas.first { $0.app == app }?.defaults
    }

    func set(_ app: String, _ key: String, _ value: SuiteValue) {
        guard let store = stores[app], SettingsPath.get(store.value, key) != value else { return }
        remember(app, key)
        store.update { SettingsPath.set(&$0, key, value) }
        self.ingest(app, store.value)
    }

    // MARK: - отмена

    private struct Step {
        let app: String
        let key: String
        let snapshot: [String: SuiteValue]
        var at: Date
    }

    private(set) var undoCount = 0
    private(set) var redoCount = 0
    @ObservationIgnored private var undoStack: [Step] = []
    @ObservationIgnored private var redoStack: [Step] = []

    /// Серия правок одного поля подряд (ползунок, ручка в превью) - это один шаг отмены.
    private func remember(_ app: String, _ key: String) {
        guard let current = stores[app]?.value else { return }
        let now = Date()
        if let last = undoStack.last, last.app == app, last.key == key, now.timeIntervalSince(last.at) < 1 {
            undoStack[undoStack.count - 1].at = now
        } else {
            undoStack.append(Step(app: app, key: key, snapshot: current, at: now))
            if undoStack.count > 200 { undoStack.removeFirst() }
        }
        redoStack.removeAll()
        undoCount = undoStack.count
        redoCount = 0
    }

    func undo() { travel(from: &undoStack, to: &redoStack) }
    func redo() { travel(from: &redoStack, to: &undoStack) }

    private func travel(from: inout [Step], to: inout [Step]) {
        guard let step = from.popLast(), let store = stores[step.app] else { return }
        to.append(Step(app: step.app, key: step.key, snapshot: store.value, at: .distantPast))
        store.update { $0 = step.snapshot }
        self.ingest(step.app, store.value)
        selection = step.app
        undoCount = undoStack.count
        redoCount = redoStack.count
    }

    // MARK: - поле

    /// Поле, которое сейчас правят ручкой в превью: инспектор прокручивается к нему и подсвечивает.
    var focusKey: String?
    /// Страница или строка, которую попросило открыть другое приложение набора (см. `showModule`).
    var pendingTarget: String?

    func isDefault(_ app: String, _ field: SuiteSchema.Field) -> Bool {
        guard let defaults = schemas.first(where: { $0.app == app })?.defaults else { return true }
        return [field.key, field.modifiersKey].compactMap { $0 }.allSatisfy { key in
            defaults[key] == nil || value(app, key) == defaults[key]
        }
    }

    func reset(_ app: String, _ field: SuiteSchema.Field) {
        guard let defaults = schemas.first(where: { $0.app == app })?.defaults else { return }
        for key in [field.key, field.modifiersKey].compactMap({ $0 }) {
            if let value = defaults[key] { set(app, key, value) }
        }
    }

    /// Файл настроек приложения как JSON: его получают живые превью (перерисовываются на любую правку).
    func settingsData(_ app: String) -> Data {
        _ = revision(app).count
        return (try? JSONEncoder().encode(values[app] ?? [:])) ?? Data()
    }

    func field(_ app: String, _ key: String) -> SuiteSchema.Field? {
        fieldIndex[app]?[key]
    }

    private static func index(_ schema: SuiteSchema) -> [String: SuiteSchema.Field] {
        Dictionary(schema.groups.flatMap(\.fields).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Число в пределах и с шагом, заданными схемой (для ручек в превью).
    func setNumber(_ app: String, _ key: String, _ value: Double) {
        var value = value
        if let field = field(app, key) {
            if let step = field.step, step > 0 { value = (value / step).rounded() * step }
            value = min(max(value, field.min ?? -.infinity), field.max ?? .infinity)
        }
        set(app, key, .number(value))
    }

    func number(_ app: String, _ key: String) -> Double {
        value(app, key)?.number ?? 0
    }

    /// Совпадают ли все поля схемы со значениями по умолчанию. Следит за всем файлом, а не за сотнями ячеек.
    func isDefault(_ schema: SuiteSchema) -> Bool {
        _ = revision(schema.app).count
        let file = values[schema.app] ?? [:]
        return schema.groups.flatMap(\.fields).allSatisfy { field in
            [field.key, field.modifiersKey].compactMap { $0 }.allSatisfy { key in
                guard let standard = schema.defaults[key] else { return true }
                return (SettingsPath.get(file, key) ?? standard) == standard
            }
        }
    }

    /// Возвращает поля из схемы к значениям по умолчанию; остальное в файле не трогает.
    func reset(_ schema: SuiteSchema) {
        guard let store = stores[schema.app] else { return }
        remember(schema.app, "*")
        let keys = schema.groups.flatMap(\.fields).flatMap { [$0.key, $0.modifiersKey].compactMap { $0 } }
        store.update { file in
            for key in keys { SettingsPath.set(&file, key, schema.defaults[key]) }
        }
        self.ingest(schema.app, store.value)
    }

    func isVisible(_ field: SuiteSchema.Field, in app: String) -> Bool {
        guard let condition = field.visibleWhen else { return true }
        let current = value(app, condition.key)
        // Условие по переключателю пишется строкой «true» / «false».
        let text = current?.string ?? current?.bool.map { $0 ? "true" : "false" } ?? ""
        return condition.values.contains(text)
    }
}

/// Вложенные ключи через точку в файле настроек.
enum SettingsPath {
    static func get(_ root: [String: SuiteValue], _ key: String) -> SuiteValue? {
        let parts = key.split(separator: ".").map(String.init)
        guard parts.count > 1 else { return root[key] }
        var current: SuiteValue? = .object(root)
        for part in parts {
            guard case let .object(object)? = current else { return nil }
            current = object[part]
        }
        return current
    }

    /// nil - убрать ключ.
    static func set(_ root: inout [String: SuiteValue], _ key: String, _ value: SuiteValue?) {
        let parts = key.split(separator: ".").map(String.init)
        guard parts.count > 1 else { root[key] = value; return }
        root = setting(root, parts[...], value)
    }

    private static func setting(_ object: [String: SuiteValue], _ parts: ArraySlice<String>,
                                _ value: SuiteValue?) -> [String: SuiteValue] {
        var object = object
        guard let head = parts.first else { return object }
        if parts.count == 1 {
            object[head] = value
        } else {
            var child: [String: SuiteValue] = [:]
            if case let .object(existing)? = object[head] { child = existing }
            object[head] = .object(setting(child, parts.dropFirst(), value))
        }
        return object
    }
}
