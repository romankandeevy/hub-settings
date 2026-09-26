import AppKit
import SuiteKit

/// Где лежат настройки приложения: хаб одинаково правит `settings.json` набора (`SuiteStore`)
/// и UserDefaults приложений, которые хранят настройки там (`DefaultsStore`).
@MainActor
protocol SettingsStore: AnyObject {
    var value: [String: SuiteValue] { get }
    func update(_ change: (inout [String: SuiteValue]) -> Void)
}

extension SuiteStore: SettingsStore where Value == [String: SuiteValue] {}

/// Приложения набора, которые хранят настройки в своих UserDefaults, а не в `settings.json`
/// (Flow, Awake). Их схему хаб описывает сам - ключи и значения те же, что читает приложение.
/// Записав значение, хаб присылает приложению распределённое уведомление, и оно применяет его сразу.
struct ExternalSettings {
    let schema: SuiteSchema
    let bundleID: String
    let notification: String
    /// Ключи, которые хаб правит своими секциями, а не полями схемы (замены Flow). «Сбросить» их не трогает.
    var extraKeys: [String] = []

    @MainActor static var all: [ExternalSettings] { [awake, flow] }

    /// Только установленные: неустановленному приложению настраивать нечего.
    @MainActor static var installed: [ExternalSettings] {
        all.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    private static func schema(_ schema: SuiteSchema, defaults: [String: SuiteValue]) -> SuiteSchema {
        var copy = schema
        copy.defaults = defaults
        return copy
    }

    private static let awake = ExternalSettings(
        schema: schema(SuiteSchema(
            app: "awake", title: "Awake", symbol: "cup.and.saucer.fill",
            summary: "Не даёт Mac уснуть, пока вы отошли.",
            groups: [
                .init("Режим", footer: "Закрытая крышка всё равно усыпляет Mac - это обычный сон.", fields: [
                    .toggle("on", "Не давать Mac уснуть", help: "Программы продолжают работать, пока вы отошли"),
                    .toggle("keepDisplay", "Не гасить экран", help: "Пока режим включён"),
                ]),
                .init("Запуск", fields: [
                    .toggle("launchAtLogin", "Открывать при входе в систему"),
                ]),
                .init("Сочетание клавиш", footer: "Включает и выключает режим, не открывая меню.", fields: [
                    .toggle("hotkeyEnabled", "Включать сочетанием клавиш"),
                    .hotkey("hotKeyCode", modifiers: "hotKeyModifiers", "Сочетание")
                        .visible(when: "hotkeyEnabled", is: "true"),
                ]),
            ]
        ), defaults: [
            "on": .bool(false), "keepDisplay": .bool(false), "launchAtLogin": .bool(false),
            "until": .number(0), "hotkeyEnabled": .bool(true), "hotKeyCode": .number(40),
            "hotKeyModifiers": .array([.string("command"), .string("shift")]),
        ]),
        bundleID: "com.roman.awake",
        notification: "com.roman.suite.awake.settings"
    )

    /// Flow - все его настройки живут здесь: в самом приложении окна настроек больше нет.
    /// Схема собирается при каждом `reload`: список микрофонов меняется, когда их подключают.
    @MainActor private static var flow: ExternalSettings {
        let system = AudioInputs.defaultName().map { "Системный - \($0)" } ?? "Системный"
        let mics = [SuiteSchema.Field.Option("", system)] + AudioInputs.all().map { .init($0.uid, $0.name) }
        let pill = { (field: SuiteSchema.Field) in field.visible(when: "showPill", is: "true") }
        return ExternalSettings(
            schema: schema(SuiteSchema(
                app: "flow", title: "Flow", symbol: "waveform",
                summary: "Диктовка: зажмите клавишу и говорите - текст появится там, где вы печатаете.",
                groups: [
                    .init("Сочетания клавиш", footer: "Работают в любом приложении. Esc во время записи - отмена.", fields: [
                        .hotkey("holdKeyCode", modifiers: "holdModifiers", "Удерживая клавиши",
                                help: "Держите и говорите, отпустите - текст на месте"),
                        .hotkey("toggleKeyCode", modifiers: "toggleModifiers", "По нажатию",
                                help: "Нажмите, чтобы начать, и ещё раз, чтобы вставить"),
                    ]),
                    .init("Распознавание", fields: [
                        .choice("langMode", "Язык", help: "«Авто» различает русский и английский по ходу речи", options: [
                            .init("auto", "Авто"), .init("ru", "Русский"), .init("en", "English"),
                        ]),
                    ]),
                    .init("Вставка", fields: [
                        .toggle("insertAutomatically", "Вставлять текст в активное окно",
                                help: "Иначе текст остаётся только в ленте"),
                        .toggle("addSpace", "Пробел после текста", help: "Следующая диктовка не прилипнет к предыдущей")
                            .visible(when: "insertAutomatically", is: "true"),
                        .toggle("keepInClipboard", "Оставлять текст в буфере обмена",
                                help: "Иначе вернётся то, что было в буфере до диктовки")
                            .visible(when: "insertAutomatically", is: "true"),
                    ]),
                    .init("Микрофон", footer: "Микрофон слушает, только пока идёт запись.", fields: [
                        .choice("micUID", "Источник", options: mics),
                        .toggle("sounds", "Звук в начале и в конце записи"),
                    ]),
                    .init("Капсула записи", footer: "Выключите всё, что видно во время записи, - останется одна красная точка.", fields: [
                        .toggle("showPill", "Показывать капсулу", help: "Поверх всех окон, пока идёт запись"),
                        pill(.choice("pillPosition", "Место на экране", options: [.init("bottom", "Внизу"), .init("top", "Вверху")])),
                        pill(.choice("pillSize", "Размер", options: [
                            .init("compact", "Мелкая"), .init("regular", "Обычная"), .init("large", "Крупная"),
                        ])),
                        pill(.toggle("pillShowDot", "Красная точка")),
                        pill(.toggle("pillShowTimer", "Время записи", help: "Сколько уже идёт диктовка")),
                        pill(.toggle("pillShowWave", "Уровень звука", help: "Волна: видно, что микрофон слышит")),
                        pill(.toggle("pillLiveText", "Текст в реальном времени",
                                     help: "Последние распознанные слова бегущей строкой")),
                        .choice("pillTextWidth", "Ширина текста", options: [
                            .init("narrow", "Узкая"), .init("medium", "Средняя"), .init("wide", "Широкая"),
                        ]).visible(when: "pillLiveText", is: "true"),
                        pill(.toggle("pillShowStatus", "«Распознаю…» и «Готово» после записи",
                                     help: "Выключите - капсула исчезнет сразу, как отпустите клавишу")),
                    ]),
                    .init("Чистка текста", footer: "Ошибки и «Текст скопирован, нажмите ⌘V» видны всегда.", fields: [
                        .choice("cleanupLevel", "Слова-паразиты", options: [
                            .init("off", "Не убирать"), .init("hesitations", "Только заминки"),
                            .init("fillers", "Паразиты"), .init("strict", "Строго"),
                        ]),
                        .toggle("removeRepeats", "Убирать повторы", help: "«я я хотел» → «я хотел»"),
                        .toggle("capitalize", "Заглавная в начале фразы"),
                        .toggle("trailingPeriod", "Точка в конце", help: "Выключите для чатов - сообщения без точки"),
                        .text("customFillers", "Свои слова-паразиты", help: "Через запятую",
                              placeholder: "слышь, прикинь, это самое"),
                    ]),
                    .init("История", fields: [
                        .toggle("saveAudio", "Сохранять звук диктовок",
                                help: "Чтобы прослушать и распознать заново. Около 2 МБ в минуту"),
                        .choice("historyDays", "Хранить диктовки", help: "Старые удаляются вместе со звуком", options: [
                            .init("7", "Неделю"), .init("30", "Месяц"), .init("90", "3 месяца"), .init("0", "Всегда"),
                        ]),
                    ]),
                    .init("Оформление", footer: "Хотя бы один значок остаётся: без обоих до окна Flow не добраться.", fields: [
                        .choice("appearance", "Тема", help: "Окно и капсула записи", options: [
                            .init("system", "Как в системе"), .init("light", "Светлая"), .init("dark", "Тёмная"),
                        ]),
                        .toggle("launchAtLogin", "Открывать при входе в систему"),
                        .toggle("showMenuBarIcon", "Значок в строке меню", help: "Состояние записи и быстрый старт диктовки"),
                        .toggle("showInDock", "Значок в Доке", help: "Без него Flow живёт только в строке меню"),
                    ]),
                ]
            ), defaults: [
                "holdKeyCode": .number(49), "holdModifiers": .array([.string("control"), .string("shift")]),
                "toggleKeyCode": .number(49), "toggleModifiers": .array([.string("option")]),
                "langMode": .string("auto"),
                "insertAutomatically": .bool(true), "addSpace": .bool(true), "keepInClipboard": .bool(false),
                "micUID": .string(""), "sounds": .bool(false),
                "showPill": .bool(true), "pillPosition": .string("bottom"), "pillSize": .string("regular"),
                "pillShowDot": .bool(true), "pillShowTimer": .bool(true), "pillShowWave": .bool(true),
                "pillLiveText": .bool(true), "pillTextWidth": .string("medium"), "pillShowStatus": .bool(true),
                "cleanupLevel": .string("fillers"), "removeRepeats": .bool(true), "capitalize": .bool(true),
                "trailingPeriod": .bool(true), "customFillers": .string(""),
                "saveAudio": .bool(true), "historyDays": .string("0"),
                "appearance": .string("system"), "launchAtLogin": .bool(false),
                "showMenuBarIcon": .bool(true), "showInDock": .bool(true),
            ]),
            bundleID: "com.flowlocal.mac",
            notification: "com.roman.suite.flow.settings",
            extraKeys: ["replacements"]
        )
    }
}

/// Настройки приложения в его UserDefaults. Читает и пишет только ключи из схемы.
@MainActor
final class DefaultsStore: SettingsStore {
    private(set) var value: [String: SuiteValue]
    var onChange: (([String: SuiteValue]) -> Void)?
    private let domain: CFString
    private let keys: [String]
    private let notification: Notification.Name
    private var observer: NSObjectProtocol?

    init(_ settings: ExternalSettings) {
        domain = settings.bundleID as CFString
        keys = settings.schema.groups.flatMap(\.fields).flatMap { [$0.key, $0.modifiersKey].compactMap { $0 } }
            + settings.extraKeys
        notification = Notification.Name(settings.notification)
        value = [:]
        value = read()
        // Приложение само поправило настройку (не дало спрятать оба значка, вход в систему не включился) -
        // присылает «<уведомление>.changed», и хаб показывает то, что есть на самом деле.
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(settings.notification + ".changed"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func update(_ change: (inout [String: SuiteValue]) -> Void) {
        var next = value
        change(&next)
        let changed = keys.filter { next[$0] != value[$0] }
        guard !changed.isEmpty else { return }
        for key in changed {
            CFPreferencesSetAppValue(key as CFString, next[key].flatMap(Self.plist), domain)
        }
        CFPreferencesAppSynchronize(domain)
        value = next
        DistributedNotificationCenter.default().postNotificationName(notification, object: nil, userInfo: nil,
                                                                     deliverImmediately: true)
    }

    /// Приложение могло поменять настройку у себя - перечитываем, когда возвращаемся в окно хаба.
    func refresh() {
        let fresh = read()
        guard fresh != value else { return }
        value = fresh
        onChange?(fresh)
    }

    private func read() -> [String: SuiteValue] {
        CFPreferencesAppSynchronize(domain)
        var result: [String: SuiteValue] = [:]
        for key in keys {
            if let raw = CFPreferencesCopyAppValue(key as CFString, domain), let value = Self.value(raw) {
                result[key] = value
            }
        }
        return result
    }

    private static func value(_ raw: CFPropertyList) -> SuiteValue? {
        if CFGetTypeID(raw) == CFBooleanGetTypeID() { return .bool(CFBooleanGetValue((raw as! CFBoolean))) }
        if let number = raw as? NSNumber { return .number(number.doubleValue) }
        if let text = raw as? String { return .string(text) }
        if let list = raw as? [Any] { return .array(list.compactMap { value($0 as CFPropertyList) }) }
        return nil
    }

    private static func plist(_ value: SuiteValue) -> CFPropertyList? {
        switch value {
        case .bool(let v): v as CFBoolean
        case .number(let v): (v.rounded() == v ? NSNumber(value: Int(v)) : NSNumber(value: v)) as CFNumber
        case .string(let v): v as CFString
        case .array(let v): v.compactMap(plist) as CFArray
        case .object, .null: nil
        }
    }
}
