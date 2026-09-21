import AppKit
import Observation
import SuiteKit

/// Все приложения набора, которые опубликовали схему настроек, и их текущие значения.
/// Хаб правит `settings.json` через `SuiteStore`: приложение подхватывает изменение сразу,
/// а если файл поменяли снаружи (само приложение или руками), хаб тоже это видит.
@MainActor
@Observable
final class HubModel {
    private(set) var schemas: [SuiteSchema] = []
    private(set) var values: [String: [String: SuiteValue]] = [:]
    var selection: String? {
        didSet { UserDefaults.standard.set(selection, forKey: "selection") }
    }

    @ObservationIgnored private var stores: [String: SuiteStore<[String: SuiteValue]>] = [:]
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        selection = UserDefaults.standard.string(forKey: "selection")
        reload()
        // Новое приложение или новая версия схемы появляются, когда возвращаешься в окно хаба.
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    var selected: SuiteSchema? {
        schemas.first { $0.app == selection } ?? schemas.first
    }

    func reload() {
        let fresh = SuiteSchema.installed()
        if fresh != schemas { schemas = fresh }
        for schema in fresh where stores[schema.app] == nil {
            let store = SuiteStore(app: schema.app, name: schema.file, default: schema.defaults)
            store.onChange = { [weak self] value in self?.values[schema.app] = value }
            stores[schema.app] = store
            values[schema.app] = store.value
        }
    }

    func value(_ app: String, _ key: String) -> SuiteValue? {
        values[app]?[key] ?? schemas.first { $0.app == app }?.defaults[key]
    }

    func set(_ app: String, _ key: String, _ value: SuiteValue) {
        guard let store = stores[app], store.value[key] != value else { return }
        remember(app, key)
        store.update { $0[key] = value }
        values[app] = store.value
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
        values[step.app] = store.value
        selection = step.app
        undoCount = undoStack.count
        redoCount = redoStack.count
    }

    // MARK: - поле

    /// Поле, которое сейчас правят ручкой в превью: инспектор прокручивается к нему и подсвечивает.
    var focusKey: String?

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

    /// Файл настроек приложения как JSON: его получают живые превью.
    func settingsData(_ app: String) -> Data {
        (try? JSONEncoder().encode(values[app] ?? [:])) ?? Data()
    }

    func field(_ app: String, _ key: String) -> SuiteSchema.Field? {
        schemas.first { $0.app == app }?.groups.flatMap(\.fields).first { $0.key == key }
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

    /// Совпадают ли все поля схемы со значениями по умолчанию.
    func isDefault(_ schema: SuiteSchema) -> Bool {
        schema.groups.flatMap(\.fields).allSatisfy { field in
            [field.key, field.modifiersKey].compactMap { $0 }.allSatisfy { key in
                schema.defaults[key] == nil || value(schema.app, key) == schema.defaults[key]
            }
        }
    }

    /// Возвращает поля из схемы к значениям по умолчанию; остальное в файле не трогает.
    func reset(_ schema: SuiteSchema) {
        guard let store = stores[schema.app] else { return }
        remember(schema.app, "*")
        let keys = schema.groups.flatMap(\.fields).flatMap { [$0.key, $0.modifiersKey].compactMap { $0 } }
        store.update { file in
            for key in keys { file[key] = schema.defaults[key] }
        }
        values[schema.app] = store.value
    }

    func isVisible(_ field: SuiteSchema.Field, in app: String) -> Bool {
        guard let condition = field.visibleWhen else { return true }
        return condition.values.contains(value(app, condition.key)?.string ?? "")
    }
}
