import SuiteKit
import SwiftUI

/// Модуль из опубликованной схемы приложения (`RomanSuite/<app>/schema.json`). Любое приложение набора,
/// которое публикует схему, попадает в окно само: в боковой список, в поиск и на свой экран.
struct SchemaModule: SettingsModule {
    let schema: SuiteSchema
    let model: HubModel
    let apps: AppMonitor

    private var style: ModuleStyle { ModuleCatalog.style(for: schema.app) }

    var id: String { schema.app }
    var title: String { schema.title }
    var summary: String { style.summary ?? schema.summary ?? "" }
    var symbol: String { schema.symbol }
    var tint: Color { style.tint ?? TileColor.stable(for: schema.app) }

    var power: ModulePower? {
        let app = schema.app
        let installed = apps.isInstalled(app)
        return ModulePower(
            isOn: apps.isRunning(app),
            isBusy: apps.isBusy(app),
            note: installed ? nil : "Приложение \(schema.title) не найдено: сначала установите его.",
            available: installed,
            set: { on in apps.setRunning(app, on) }
        )
    }

    var sections: [SettingsSection] { layout.sections }
    var pageGroups: [PageGroup] { layout.pages }

    /// Раскладка модуля: секции главной страницы и подстраницы. Считается один раз на отрисовку экрана.
    private var layout: (sections: [SettingsSection], pages: [PageGroup]) {
        SchemaLayout(schema: schema, style: style, model: model).build()
    }

    var canReset: Bool { !model.isDefault(schema) }
    var reset: (() -> Void)? { { [model, schema] in model.reset(schema) } }
}

// MARK: - приложение без настроек

/// Приложение набора, у которого нет своих настроек (схемы): в окне его можно только включить и выключить.
struct AppOnlyModule: SettingsModule {
    let app: AppMonitor.SuiteApp
    let apps: AppMonitor

    private var style: ModuleStyle { ModuleCatalog.style(for: app.id) }

    var id: String { app.id }
    var title: String { style.title ?? app.name }
    var summary: String { style.summary ?? "" }
    var symbol: String { style.symbol ?? "app.fill" }
    var tint: Color { style.tint ?? TileColor.stable(for: app.id) }

    var power: ModulePower? {
        let id = app.id
        return ModulePower(isOn: apps.isRunning(id), isBusy: apps.isBusy(id), set: { on in apps.setRunning(id, on) })
    }

    var sections: [SettingsSection] {
        [SettingsSection(id: "\(app.id).about", footer: "Остальное настраивается в самом приложении.", options: [
            SettingsOption(id: "\(app.id).nosettings", title: "Настроек здесь нет") {
                Text("У \(title) нет настроек в хабе - только включение и выключение.")
                    .foregroundStyle(.secondary)
            },
        ])]
    }
}

// MARK: - оформление модулей

/// Как модуль выглядит в окне: цвет плитки, строка описания, порядок секций и подписи простыми словами.
/// Всё это только интерфейс: ключи и значения в файлах настроек те же, что публикует приложение.
struct ModuleStyle {
    var tint: Color?
    /// Для приложений без схемы: название и значок (у приложений со схемой они из схемы).
    var title: String?
    var symbol: String?
    var summary: String?
    var layout: [SectionLayout] = []
    var copy: [String: FieldCopy] = [:]
    /// Подстраницы по группам. Параметры вкладок и функций (`moduleOptions.<id>.…`), которых здесь нет,
    /// всё равно появятся - на своей странице в группе «Другое».
    var pages: [PageSpec.Group] = []
    /// Не показывать: служебное или то, что и так переключается прямо в приложении.
    var hidden: Set<String> = []
    /// Технические настройки: в свёрнутой секции «Для задротов» внизу своей страницы.
    var advanced: Set<String> = []
    /// Убраны из настроек: поведение всегда как по умолчанию в схеме. Хаб их не показывает
    /// и возвращает к значению по умолчанию, если в файле осталось другое (`HubModel.pinFixed`).
    var fixed: Set<String> = []

    /// Не показывать в окне и в поиске.
    func isHidden(_ key: String) -> Bool { hidden.contains(key) || fixed.contains(key) }

    struct SectionLayout {
        let title: String
        var footer: String?
        let keys: [String]
    }

    func copy(for field: SuiteSchema.Field) -> FieldCopy {
        var copy = copy[field.key] ?? FieldCopy()
        if copy.title.isEmpty { copy.title = field.title }
        if copy.help == nil { copy.help = field.help }
        if copy.help?.isEmpty == true { copy.help = nil }
        return copy
    }
}

/// Подпись поля и то, как показывать его значение.
struct FieldCopy {
    var title = ""
    /// Строка пояснения под подписью. Пустая строка - убрать пояснение из схемы.
    var help: String?
    var value: ValueFormat = .plain

    enum ValueFormat {
        /// Число с единицей из схемы.
        case plain
        /// Доля от 0 до 1 - в процентах.
        case percent
        /// Без числа: подписи по краям ползунка («Выше» … «Ниже»).
        case ends(String, String)
    }

    init(_ title: String = "", help: String? = nil, value: ValueFormat = .plain) {
        self.title = title
        self.help = help
        self.value = value
    }
}

/// Оформление известных модулей. Модуль, которого здесь нет, всё равно появится: с цветом по имени
/// и подписями из своей схемы.
enum ModuleCatalog {
    static func style(for app: String) -> ModuleStyle {
        switch app {
        case "island": island
        case "sidebar": sidebar
        case "shelf": shelf
        case "flow": flow
        case "horizon": horizon
        case "awake": ModuleStyle(tint: TileColor.yellow, symbol: "cup.and.saucer.fill")
        default: ModuleStyle()
        }
    }

    private static let island = ModuleStyle(
        tint: TileColor.indigo,
        summary: "Остров в чёлке MacBook: музыка, полка файлов, таймер и лимиты Claude.",
        layout: [
            .init(title: "Вкладки",
                  footer: "Порядок - как в раскрытом острове. Перетащите строку, чтобы переставить вкладку.",
                  keys: ["tabs"]),
            .init(title: "По бокам от чёлки",
                  footer: "Что видно слева и справа от чёлки, когда остров свёрнут и ничего не происходит.",
                  keys: ["idleLeft", "idleRight", "shelfInEars", "shelfEar", "lowBattery", "earFontSize", "rotationInterval"]),
            .init(title: "Поведение", keys: ["openOnFileDrag", "hoverDelay", "hideDelay", "haptics", "animationSpeed"]),
        ],
        copy: [
            "tabs": FieldCopy("Вкладки"),
            "idleLeft": FieldCopy("Слева"),
            "idleRight": FieldCopy("Справа"),
            "shelfInEars": FieldCopy("Показывать полку, если в ней есть файлы", help: "Значок полки и сколько в ней файлов"),
            "shelfEar": FieldCopy("Сторона для полки", help: "Вторая сторона показывает выбранное выше"),
            "rotationInterval": FieldCopy("Менять события каждые", help: "Когда событий больше двух"),
            "earFontSize": FieldCopy("Размер текста"),
            "lowBattery": FieldCopy("Заряд краснеет ниже"),
            "hoverDelay": FieldCopy("Раскрывать через", help: "Сколько держать курсор на острове"),
            "hideDelay": FieldCopy("Сворачивать через", help: "После того как курсор ушёл с острова"),
            "openOnFileDrag": FieldCopy("Раскрывать полку, когда тянете файл к острову"),
            "animationSpeed": FieldCopy("Скорость анимаций", help: "1× - обычная"),
            "haptics": FieldCopy("Отклик трекпада"),
            "sideWidth": FieldCopy("Ширина по бокам от чёлки", help: "Сколько свёрнутый остров выступает по бокам"),
            "extraHeight": FieldCopy("Высота свёрнутого", help: "На сколько остров опускается ниже чёлки"),
            "accent": FieldCopy("Цвет акцента", help: "Кнопки, таймер и события"),
            "peekCorner": FieldCopy("Скругление свёрнутого"),
            "earRadius": FieldCopy("Скругление у края экрана", help: "Уголки, которыми остров переходит в верх экрана"),
            "shadow": FieldCopy("Тень", value: .percent),
            "glassStyle": FieldCopy("Фон"),
            "glassBlur": FieldCopy("Размытие", help: "0 - прозрачное стекло, 10 - матовое, как у системы"),
            "glassTint": FieldCopy("Оттенок стекла"),
            "glassTintAmount": FieldCopy("Сила оттенка", help: "0% - стекло без оттенка", value: .percent),
            "glassFade": FieldCopy("Переход от чёрного к стеклу", help: "Какую часть высоты он занимает", value: .percent),
            "glassBottomShade": FieldCopy("Затемнение снизу", help: "У нижнего края острова", value: .percent),
            "tabHeight": FieldCopy("Высота кнопок вкладок"),
            "tabSpacing": FieldCopy("Расстояние между кнопками"),
            "tabCorner": FieldCopy("Скругление кнопок"),
            "tabIconSize": FieldCopy("Размер значков вкладок"),
            "shelfTileSize": FieldCopy("Размер карточек снимков"),
            "musicEnabled": FieldCopy("Показывать, что играет", help: "Обложка, эквалайзер и управление плеером"),
            "weatherCity": FieldCopy("Город", help: "Пусто - место определяет macOS. С VPN она часто ошибается, тогда впишите город"),
            "claudeUsageAPI": FieldCopy("Точные лимиты Claude с сервера",
                                        help: "Ключ берётся из Claude Code. Формально это против правил Anthropic"),
            "minimalMode": FieldCopy("Узкий остров", help: "Раскрывается уже, только музыка, события и таймер"),
            "minimalWidth": FieldCopy("Ширина узкого острова"),
            "minimalTabs": FieldCopy("Вкладки узкого острова"),
            "display": FieldCopy("Экран"),
            // Параметры вкладок и функций - простыми словами.
            "moduleOptions.shelf.onlyCaptures": FieldCopy("Из папки снимков - только снимки и записи"),
            "moduleOptions.shelf.sourceResults": FieldCopy("Результаты конвертации"),
            "moduleOptions.shelf.quality": FieldCopy("Качество при смене формата", value: .percent),
            "moduleOptions.shelf.compressQuality": FieldCopy("Качество кнопки «Сжать»", value: .percent),
            "moduleOptions.shelf.enhanceScale": FieldCopy("Улучшение: во сколько раз увеличить"),
            "moduleOptions.shelf.vectorColors": FieldCopy("SVG: число цветов"),
            "moduleOptions.shelf.vectorDetail": FieldCopy("SVG: детали"),
            "moduleOptions.shelf.vectorSmooth": FieldCopy("SVG: сглаживание"),
            "moduleOptions.timer.earsMode": FieldCopy("Какой таймер в свёрнутом острове"),
            "moduleOptions.notes.direction": FieldCopy("Куда синхронизировать"),
            "moduleOptions.claude.warnAt": FieldCopy("Предупреждать с"),
            "moduleOptions.claude.criticalAt": FieldCopy("Критично с"),
            "moduleOptions.claude.showInEars": FieldCopy("Предупреждать у чёлки", help: "Коротко, когда лимит переходит порог"),
            "moduleOptions.mirror.fit": FieldCopy("Кадр"),
            "moduleOptions.sneakPeek.onlyWhenHidden": FieldCopy("Не показывать, если плеер на экране"),
            "moduleOptions.lyrics.showPlain": FieldCopy("Текст без синхронизации, если другого нет"),
            "moduleOptions.gestures.horizontalEnabled": FieldCopy("Свайп вбок над музыкой"),
            "moduleOptions.lockScreen.opacity": FieldCopy("Непрозрачность", value: .percent),
            "moduleOptions.statsWindow.opacity": FieldCopy("Непрозрачность", value: .percent),
            "moduleOptions.awake.enabled": FieldCopy("Значок у чёлки, пока Mac не спит"),
        ],
        pages: [
            .init(title: "Остров", pages: [
                PageSpec("look", "Внешний вид", symbol: "paintbrush.fill", tint: TileColor.indigo,
                         subtitle: "Цвет, стекло и форма",
                         sections: [
                             .init(title: "Цвет", keys: ["accent"]),
                             .init(title: "Стекло",
                                   footer: "Фон раскрытого острова. Полоса чёлки всегда чёрная, ниже чёрный плавно переходит в стекло.",
                                   keys: ["glassStyle", "glassTint", "glassBlur", "glassTintAmount", "glassFade", "glassBottomShade"]),
                             .init(title: "Форма",
                                   footer: "Размер раскрытого острова подстраивается под вкладку сам. Свёрнутый можно тянуть мышью за края в превью.",
                                   keys: ["shadow", "sideWidth", "extraHeight", "peekCorner", "earRadius",
                                          "tabHeight", "tabSpacing", "tabCorner", "tabIconSize"]),
                         ]),
                PageSpec("mode", "Узкий режим и экран", symbol: "rectangle.compress.vertical", tint: TileColor.gray,
                         subtitle: "Какой экран и узкий вид острова",
                         sections: [
                             .init(title: "Раскрытие",
                                   footer: "Остров всегда свёрнутый: только то, что видно в покое.",
                                   keys: ["neverOpens"]),
                             .init(title: "Экран",
                                   footer: "На мониторе без выреза остров рисует свою «чёлку».",
                                   keys: ["display"]),
                             .init(title: "Узкий остров",
                                   footer: "Быстро переключается в меню острова по правому клику.",
                                   keys: ["minimalMode", "minimalWidth", "minimalTabs"]),
                         ]),
            ]),
            .init(title: "Вкладки", footer: "Страницы вкладок, у которых есть свои настройки.", pages: [
                PageSpec("music", "Музыка", symbol: "music.note", tint: TileColor.pink,
                         subtitle: "Обложка, эквалайзер, текст песни", power: .key("musicEnabled"), tab: "music",
                         children: [
                             PageSpec("sneakPeek", "Новый трек у чёлки", symbol: "music.note.list", tint: TileColor.pink,
                                      subtitle: "Коротко показывает, что заиграло",
                                      power: .key("moduleOptions.sneakPeek.enabled")),
                             PageSpec("lyrics", "Текст песни", symbol: "quote.bubble.fill", tint: TileColor.purple,
                                      power: .key("moduleOptions.lyrics.enabled")),
                             PageSpec("visualizer", "Эквалайзер под музыку", symbol: "waveform", tint: TileColor.red,
                                      subtitle: "Столбики пляшут в такт звуку",
                                      power: .key("moduleOptions.visualizer.enabled")),
                             PageSpec("glow", "Подсветка острова", symbol: "sun.max.fill", tint: TileColor.orange,
                                      subtitle: "Свечение цветом обложки",
                                      power: .key("moduleOptions.glow.enabled")),
                             PageSpec("musicLikes", "Лайки в плеерах", symbol: "heart.fill", tint: TileColor.red,
                                      power: .key("moduleOptions.musicLikes.enabled")),
                         ]),
                PageSpec("shelf", "Полка", symbol: "tray.full.fill", tint: TileColor.orange,
                         subtitle: "Файлы, снимки, конвертация", tab: "shelf"),
                PageSpec("clipboard", "Буфер обмена", symbol: "doc.on.clipboard.fill", tint: TileColor.blue,
                         subtitle: "История скопированного", tab: "clipboard"),
                PageSpec("timer", "Таймер", symbol: "timer", tint: TileColor.orange,
                         subtitle: "Помодоро, несколько таймеров, звук", tab: "timer"),
                PageSpec("claude", "Лимиты ИИ", symbol: "sparkles", tint: TileColor.brown,
                         subtitle: "Claude, Codex, Cursor, Gemini", tab: "claude",
                         sections: [.init(title: "Claude", keys: ["claudeUsageAPI"])]),
                PageSpec("monitor", "Монитор", symbol: "gauge.with.dots.needle.67percent", tint: TileColor.green,
                         subtitle: "Процессор, память, сеть", tab: "monitor",
                         children: [
                             PageSpec("statsWindow", "Окно со статистикой", symbol: "square.on.square.dashed", tint: TileColor.green,
                                      subtitle: "Маленькое окно поверх остальных",
                                      power: .key("moduleOptions.statsWindow.enabled")),
                         ]),
                PageSpec("weather", "Погода", symbol: "cloud.sun.fill", tint: TileColor.cyan, tab: "weather",
                         sections: [.init(title: "Место", keys: ["weatherCity"])]),
                PageSpec("notes", "Заметка", symbol: "note.text", tint: TileColor.yellow,
                         subtitle: "Синхронизация с Apple Notes", tab: "notes"),
                PageSpec("screenshots", "Снимки экрана", symbol: "camera.viewfinder", tint: TileColor.teal, tab: "screenshots",
                         sections: [.init(title: "Вид", keys: ["shelfTileSize"])]),
                PageSpec("sound", "Звук", symbol: "speaker.wave.2.fill", tint: TileColor.pink,
                         subtitle: "Громкость по приложениям", tab: "sound"),
                PageSpec("terminal", "Терминал", symbol: "apple.terminal.fill", tint: TileColor.gray, tab: "terminal"),
                PageSpec("mirror", "Зеркало", symbol: "person.crop.square.fill", tint: TileColor.teal,
                         subtitle: "Камера в острове", tab: "mirror"),
                PageSpec("assistant", "Помощник", symbol: "sparkle.magnifyingglass", tint: TileColor.purple,
                         subtitle: "Вопрос про то, что на экране", tab: "assistant"),
            ]),
            .init(title: "События у чёлки",
                  footer: "Появляются по бокам от чёлки, когда что-то происходит.", pages: [
                PageSpec("downloads", "Загрузки", symbol: "arrow.down.circle.fill", tint: TileColor.cyan,
                         power: .key("moduleOptions.downloads.enabled")),
                PageSpec("bluetooth", "Наушники и Bluetooth", symbol: "airpods", tint: TileColor.blue,
                         subtitle: "Подключение и заряд", power: .key("moduleOptions.bluetooth.enabled")),
                PageSpec("privacy", "Камера и микрофон", symbol: "video.fill", tint: TileColor.green,
                         subtitle: "Кто сейчас их держит", power: .key("moduleOptions.privacy.enabled")),
                PageSpec("screenRecording", "Запись экрана", symbol: "record.circle", tint: TileColor.red,
                         power: .key("moduleOptions.screenRecording.enabled")),
                PageSpec("focus", "Фокус", symbol: "moon.fill", tint: TileColor.indigo,
                         power: .key("moduleOptions.focus.enabled")),
                PageSpec("awake", "Не спать", symbol: "cup.and.saucer.fill", tint: TileColor.yellow,
                         subtitle: "Mac не засыпает, пока нужно", power: .key("moduleOptions.awake.enabled")),
                PageSpec("openFiles", "Файлы из терминала и Finder", symbol: "tray.and.arrow.down.fill", tint: TileColor.orange,
                         power: .key("moduleOptions.openFiles.enabled")),
            ]),
            .init(title: "Управление", pages: [
                PageSpec("hotkeys", "Сочетания клавиш", symbol: "command", tint: TileColor.gray,
                         power: .key("moduleOptions.hotkeys.enabled")),
                PageSpec("gestures", "Жесты", symbol: "hand.draw.fill", tint: TileColor.blue,
                         subtitle: "Свайпы по трекпаду у чёлки", power: .key("moduleOptions.gestures.enabled")),
                PageSpec("eyedropper", "Пипетка", symbol: "eyedropper", tint: TileColor.purple,
                         subtitle: "Цвет с любого места экрана", power: .key("moduleOptions.eyedropper.enabled")),
                PageSpec("lockScreen", "Экран блокировки", symbol: "lock.display", tint: TileColor.gray,
                         power: .key("moduleOptions.lockScreen.enabled")),
                PageSpec("urlControl", "Команды island://", symbol: "link", tint: TileColor.gray,
                         subtitle: "Для Терминала и «Быстрых команд»", power: .key("moduleOptions.urlControl.enabled")),
            ]),
        ],
        hidden: [
            // Переключаются прямо во вкладках - это текущее состояние, а не настройка.
            "moduleOptions.clipboard.paused", "moduleOptions.clipboard.incognito",
            "moduleOptions.claude.period", "moduleOptions.mirror.camera",
        ],
        advanced: [
            // Общее.
            "earFontSize", "rotationInterval", "animationSpeed",
            "glassTint", "glassBlur", "glassTintAmount", "glassFade", "glassBottomShade",
            "sideWidth", "extraHeight", "peekCorner", "earRadius", "tabHeight", "tabSpacing", "tabCorner", "tabIconSize",
            "minimalWidth", "minimalTabs",
            // Музыка.
            "moduleOptions.sneakPeek.place", "moduleOptions.sneakPeek.showArtwork",
            "moduleOptions.sneakPeek.onlyWhenHidden", "moduleOptions.sneakPeek.animated",
            "moduleOptions.sneakPeek.onResume", "moduleOptions.sneakPeek.width", "moduleOptions.sneakPeek.fontSize",
            "moduleOptions.lyrics.pinAnimated",
            "moduleOptions.lyrics.sources", "moduleOptions.lyrics.showPlain", "moduleOptions.lyrics.fontSize",
            "moduleOptions.lyrics.context", "moduleOptions.lyrics.pinOnlyPlaying", "moduleOptions.lyrics.offset",
            "moduleOptions.lyrics.pinWidth", "moduleOptions.lyrics.pinFontSize",
            "moduleOptions.visualizer.gradient", "moduleOptions.visualizer.showInEar", "moduleOptions.visualizer.showInTab",
            "moduleOptions.visualizer.source", "moduleOptions.visualizer.appBundleID", "moduleOptions.visualizer.fallbackToAll",
            "moduleOptions.visualizer.earBars", "moduleOptions.visualizer.tabBars",
            "moduleOptions.glow.where", "moduleOptions.glow.size", "moduleOptions.glow.pulse", "moduleOptions.glow.beat",
            "moduleOptions.glow.pulseStrength", "moduleOptions.glow.colorCount",
            "moduleOptions.musicLikes.others", "moduleOptions.musicLikes.spotifyPort",
            // Пятница: на виду только «каждый час», автоплейлист и «только русское».
            "moduleOptions.friday.topCount", "moduleOptions.friday.showcase", "moduleOptions.friday.genres",
            "moduleOptions.friday.genreCount", "moduleOptions.friday.artists", "moduleOptions.friday.maxArtists",
            "moduleOptions.friday.similar", "moduleOptions.friday.editorial", "moduleOptions.friday.premiere",
            "moduleOptions.friday.presaves",
            // Звук.
            "moduleOptions.sound.step", "moduleOptions.sound.showSystem",
            // Полка.
            "moduleOptions.shelf.sourceResults", "moduleOptions.shelf.sourceClipboard",
            "moduleOptions.shelf.sourceScreenshots", "moduleOptions.shelf.sourceRecordings",
            "moduleOptions.shelf.onlyCaptures", "moduleOptions.shelf.maxAgeDays", "moduleOptions.shelf.thumbSize",
            "moduleOptions.shelf.sort", "moduleOptions.shelf.showNames", "moduleOptions.shelf.showDates",
            "moduleOptions.shelf.showSizes", "moduleOptions.shelf.imageFormat", "moduleOptions.shelf.quality",
            "moduleOptions.shelf.videoSize", "moduleOptions.shelf.trashOriginal",
            "moduleOptions.shelf.enhanceScale", "moduleOptions.shelf.sharpen", "moduleOptions.shelf.denoise",
            "moduleOptions.shelf.vectorColors", "moduleOptions.shelf.vectorDetail", "moduleOptions.shelf.vectorSmooth",
            "moduleOptions.shelf.gifFPS", "moduleOptions.shelf.gifWidth", "moduleOptions.shelf.compressQuality",
            // Буфер обмена.
            "moduleOptions.clipboard.ignoreApps", "moduleOptions.clipboard.maxAgeDays",
            "moduleOptions.clipboard.images", "moduleOptions.clipboard.files",
            "moduleOptions.clipboard.imageMaxSide", "moduleOptions.clipboard.maxTextLength",
            // Таймер.
            "moduleOptions.timer.presets", "moduleOptions.timer.earsMode",
            "moduleOptions.timer.maxTimers", "moduleOptions.timer.defaultColor", "moduleOptions.timer.countBadge",
            // Заметка.
            "moduleOptions.notes.folder", "moduleOptions.notes.direction",
            "moduleOptions.notes.interval", "moduleOptions.notes.conflict",
            // Монитор и окно статистики.
            "moduleOptions.monitor.temperatureUnit", "moduleOptions.monitor.speedUnit",
            "moduleOptions.monitor.interval", "moduleOptions.monitor.topCount",
            "moduleOptions.statsWindow.opacity", "moduleOptions.statsWindow.allSpaces",
            // Лимиты ИИ.
            "moduleOptions.claude.warnAt", "moduleOptions.claude.criticalAt",
            "moduleOptions.claude.geminiDailyLimit", "moduleOptions.claude.refreshMinutes",
            // Терминал.
            "moduleOptions.terminal.shell", "moduleOptions.terminal.login", "moduleOptions.terminal.closeOnHide",
            "moduleOptions.terminal.foreground", "moduleOptions.terminal.background", "moduleOptions.terminal.cursor",
            "moduleOptions.terminal.scrollback", "moduleOptions.terminal.optionAsMeta",
            // Зеркало.
            "moduleOptions.mirror.fit", "moduleOptions.mirror.zoom", "moduleOptions.mirror.quality",
            // Помощник.
            "moduleOptions.assistant.autoSend", "moduleOptions.assistant.captureOnHotkey",
            "moduleOptions.assistant.listenOnHotkey",
            "moduleOptions.assistant.maxSide", "moduleOptions.assistant.maxLength", "moduleOptions.assistant.timeout",
            "moduleOptions.assistant.claudePath",
            // События у чёлки.
            "moduleOptions.downloads.showName", "moduleOptions.downloads.finishedDuration",
            "moduleOptions.downloads.folders", "moduleOptions.downloads.minSize",
            "moduleOptions.bluetooth.other", "moduleOptions.bluetooth.showName", "moduleOptions.bluetooth.showDisconnect",
            "moduleOptions.bluetooth.duration", "moduleOptions.bluetooth.lowThreshold", "moduleOptions.bluetooth.batteryStyle",
            "moduleOptions.screenRecording.showTimer", "moduleOptions.screenRecording.showStop",
            "moduleOptions.focus.keepWhileOn", "moduleOptions.focus.duration", "moduleOptions.focus.sound",
            // Управление.
            "moduleOptions.hotkeys.openTab1On", "moduleOptions.hotkeys.openTab1Key", "moduleOptions.hotkeys.openTab1Tab",
            "moduleOptions.hotkeys.openTab2On", "moduleOptions.hotkeys.openTab2Key", "moduleOptions.hotkeys.openTab2Tab",
            "moduleOptions.hotkeys.timerOn", "moduleOptions.hotkeys.timerKey",
            "moduleOptions.hotkeys.toggleMinimalOn", "moduleOptions.hotkeys.toggleMinimalKey",
            "moduleOptions.gestures.swipeDownOpens", "moduleOptions.gestures.swipeUpCloses",
            "moduleOptions.gestures.horizontalWhenClosed",
            "moduleOptions.gestures.seekSeconds", "moduleOptions.gestures.sensitivity",
            "moduleOptions.eyedropper.sound",
            "moduleOptions.eyedropper.uppercase", "moduleOptions.eyedropper.includeAlpha",
            "moduleOptions.eyedropper.historySize",
            "moduleOptions.lockScreen.showVolume", "moduleOptions.lockScreen.showDevices",
            "moduleOptions.lockScreen.opacity", "moduleOptions.lockScreen.unlockAnimation",
            "moduleOptions.lockScreen.scale",
        ],
        fixed: [
            "moduleOptions.sound.showIcons",
            "moduleOptions.shelf.keepPinned", "moduleOptions.clipboard.keepPinnedOnClear",
            "moduleOptions.sneakPeek.onFirstTrack", "moduleOptions.visualizer.fallback",
            "moduleOptions.glow.animateColors", "moduleOptions.notes.createIfMissing",
            "moduleOptions.awake.showAlways",
            "moduleOptions.openFiles.showActivity", "moduleOptions.openFiles.folders",
            "moduleOptions.privacy.priority", "moduleOptions.focus.showOff", "moduleOptions.claude.fetchPrices",
            "moduleOptions.eyedropper.closeIsland", "moduleOptions.eyedropper.showPopup",
            "moduleOptions.urlControl.suiteBus",
        ]
    )

    private static let flow = ModuleStyle(
        tint: TileColor.purple, title: "Flow", symbol: "waveform",
        advanced: [
            "addSpace", "keepInClipboard",
            "pillPosition", "pillSize", "pillShowTimer", "pillShowWave",
            "pillLiveText", "pillTextWidth",
            "removeRepeats", "capitalize", "customFillers",
            "saveAudio", "historyDays", "showMenuBarIcon", "showInDock",
        ],
        fixed: ["pillShowDot", "pillShowStatus"]
    )

    private static let sidebar = ModuleStyle(
        tint: TileColor.blue,
        summary: "Узкая панель виджетов у правого края экрана.",
        layout: [
            .init(title: "Появление", keys: ["mode", "hotKeyCode", "hoverDelay", "hideDelay"]),
            .init(title: "Виджеты",
                  footer: "Сверху вниз, как на панели. Перетащите строку, чтобы переставить виджет.",
                  keys: ["widgets"]),
            .init(title: "Размер и положение",
                  footer: "Панель можно двигать и мышью: наведите курсор на превью и потяните за край или за ручку со стрелками.",
                  keys: ["railWidth", "position"]),
            .init(title: "Внешний вид",
                  keys: ["cornerRadius", "earRadius", "railPadding", "widgetSpacing", "iconSize", "ringWidth",
                         "showLabels", "labelSize"]),
            .init(title: "Предупреждения цветом", keys: ["limitWarn", "limitDanger", "lowBattery"]),
        ],
        copy: [
            "mode": FieldCopy("Показывать панель"),
            "hotKeyCode": FieldCopy("Сочетание клавиш", help: "Показывает и закрепляет панель в любом режиме"),
            "hoverDelay": FieldCopy("Выезжать через", help: "Сколько держать курсор у края экрана"),
            "hideDelay": FieldCopy("Прятать через", help: "После того как курсор ушёл от края"),
            "widgets": FieldCopy("Виджеты"),
            "railWidth": FieldCopy("Ширина"),
            "position": FieldCopy("Положение по высоте", help: "", value: .ends("Выше", "Ниже")),
            "cornerRadius": FieldCopy("Скругление"),
            "earRadius": FieldCopy("Скругление у края экрана"),
            "railPadding": FieldCopy("Отступы сверху и снизу"),
            "widgetSpacing": FieldCopy("Расстояние между виджетами"),
            "iconSize": FieldCopy("Размер значков"),
            "ringWidth": FieldCopy("Толщина колец"),
            "showLabels": FieldCopy("Подписи под значками"),
            "labelSize": FieldCopy("Размер подписей"),
            "limitWarn": FieldCopy("Лимит Claude жёлтый с"),
            "limitDanger": FieldCopy("Лимит Claude красный с"),
            "lowBattery": FieldCopy("Заряд красный ниже"),
        ],
        advanced: [
            "hoverDelay", "hideDelay", "railWidth", "cornerRadius", "earRadius", "railPadding", "widgetSpacing",
            "iconSize", "ringWidth", "labelSize", "limitWarn", "limitDanger", "lowBattery",
        ]
    )

    private static let shelf = ModuleStyle(
        tint: TileColor.orange,
        summary: "Встряхните файл при перетаскивании - появится полка, чтобы его сконвертировать или сжать.",
        layout: [
            .init(title: "Встряхивание", keys: ["shakeEnabled", "shakeSensitivity", "placement"]),
            .init(title: "Лента", footer: "Недавнее показывается рядом с полкой само, ничего не копируя. Качество конвертации, сжатие и GIF - общие с островом: Island → Полка.",
                  keys: ["feedScreenshots", "feedDownloads", "feedClipboard", "feedDays"]),
        ],
        copy: [
            "shakeEnabled": FieldCopy("Открывать полку встряхиванием"),
            "shakeSensitivity": FieldCopy("Чувствительность"),
            "placement": FieldCopy("Где появляется полка"),
            "feedScreenshots": FieldCopy("Снимки и записи экрана"),
            "feedDownloads": FieldCopy("Загрузки"),
            "feedClipboard": FieldCopy("Буфер обмена"),
            "feedDays": FieldCopy("Показывать за последние"),
        ],
        advanced: ["feedDays", "shakeSensitivity"]
    )

    private static let horizon = ModuleStyle(
        advanced: [
            "sensitivity", "beatStrength", "syncAuto", "syncOffsetMs", "showDebug", "cycleMinutes",
            "wallpaperBrightness", "wallpaperFPS", "wallpaperQuality",
        ]
    )
}

// MARK: - подстраницы

/// Описание подстраницы для `ModuleStyle`: что на ней лежит и как она выглядит в списке.
struct PageSpec: Sendable {
    struct Group: Sendable {
        var title: String?
        var footer: String?
        let pages: [PageSpec]
    }

    /// Главный переключатель страницы.
    enum Power: Sendable {
        /// Поле схемы-переключатель (обычно `moduleOptions.<id>.enabled`).
        case key(String)
    }

    /// id вкладки или функции острова (`moduleOptions.<id>.…`); у страниц без них - любое уникальное имя.
    let id: String
    let title: String
    let symbol: String
    let tint: Color
    var subtitle: String?
    var power: Power?
    /// Страница вкладки: вверху переключатель «Вкладка в острове» (список `tabs`).
    var tab: String?
    /// Общие настройки (без `moduleOptions`), которые живут на этой странице: секции в заданном порядке.
    var sections: [ModuleStyle.SectionLayout] = []
    var children: [PageSpec] = []

    init(_ id: String, _ title: String, symbol: String, tint: Color, subtitle: String? = nil, power: Power? = nil,
         tab: String? = nil, sections: [ModuleStyle.SectionLayout] = [], children: [PageSpec] = []) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.subtitle = subtitle
        self.power = power
        self.tab = tab
        self.sections = sections
        self.children = children
    }

    /// Все id функций и вкладок на странице и под ней.
    var allIDs: [String] { [id] + children.flatMap(\.allIDs) }
}

/// Собирает из схемы главную страницу и подстраницы по `ModuleStyle`.
@MainActor
struct SchemaLayout {
    let schema: SuiteSchema
    let style: ModuleStyle
    let model: HubModel

    private var app: String { schema.app }

    func build() -> (sections: [SettingsSection], pages: [PageGroup]) {
        var used = Set<String>()
        let fields = schema.groups.flatMap(\.fields).filter { !style.isHidden($0.key) }
        let byKey = Dictionary(fields.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })

        // Главная страница: секции из раскладки.
        var root = sections(style.layout, byKey: byKey, used: &used)

        // Параметры вкладок и функций - по id из ключа.
        var groupsByID: [String: [SuiteSchema.Group]] = [:]
        var order: [String] = []
        for group in schema.groups {
            guard let id = group.fields.first.flatMap({ Self.optionID($0.key) }) else { continue }
            if groupsByID[id] == nil { order.append(id) }
            groupsByID[id, default: []].append(group)
        }

        var pageGroups: [PageGroup] = []
        var placed = Set<String>()
        for group in style.pages {
            let pages = group.pages.map { page(for: $0, groupsByID: groupsByID, byKey: byKey, used: &used) }
            placed.formUnion(group.pages.flatMap(\.allIDs))
            pageGroups.append(PageGroup(id: "\(app).group.\(group.title ?? "")", title: group.title,
                                        footer: group.footer, pages: pages))
        }
        // Новые функции, о которых хаб ещё не знает, - на своих страницах в «Другом».
        let others = order.filter { !placed.contains($0) }.map { id in
            page(for: PageSpec(id, Self.title(of: groupsByID[id] ?? []), symbol: "puzzlepiece.extension.fill", tint: TileColor.gray,
                               power: byKey["moduleOptions.\(id).enabled"] != nil ? .key("moduleOptions.\(id).enabled") : nil),
                 groupsByID: groupsByID, byKey: byKey, used: &used)
        }
        if !others.isEmpty { pageGroups.append(PageGroup(id: "\(app).group.others", title: "Другое", pages: others)) }

        // Всё, что приложение добавило в схему, а раскладка не знает, - на главной, в группах схемы.
        for group in schema.groups where group.fields.first.flatMap({ Self.optionID($0.key) }) == nil {
            let options = group.fields.filter { !used.contains($0.key) && !style.isHidden($0.key) }
            let visible = options.filter { !style.advanced.contains($0.key) }.compactMap(option)
            let advanced = options.filter { style.advanced.contains($0.key) }.compactMap(option)
            used.formUnion(options.map(\.key))
            if !visible.isEmpty {
                root.append(SettingsSection(id: "\(app).\(group.title)", title: group.title, footer: group.footer, options: visible))
            }
            if !advanced.isEmpty {
                root.append(SettingsSection(id: "\(app).\(group.title).advanced", title: "\(group.title): тонкая настройка",
                                            options: advanced, collapsed: true))
            }
        }
        // Секции, которые хаб рисует сам (замены Flow, папки, разрешения), - после своей секции схемы.
        for extra in ModuleExtras.sections(for: app, model: model) {
            let index = root.firstIndex { $0.title == extra.after }.map { $0 + 1 } ?? root.endIndex
            root.insert(extra.section, at: index)
        }
        return (root, pageGroups)
    }

    private func page(for spec: PageSpec, groupsByID: [String: [SuiteSchema.Group]],
                      byKey: [String: SuiteSchema.Field], used: inout Set<String>) -> SettingsPage {
        var power: PagePower?
        // Подпись переключателя, повторяющая название страницы («Текст песни» на странице «Текст песни»), - просто «Включено».
        if case let .key(key)? = spec.power, let field = byKey[key],
           let option = option(field, title: style.copy(for: field).title == spec.title || field.title == spec.title ? "Включено" : nil) {
            used.insert(key)
            power = PagePower(option: option, isOn: { [model, app] in model.value(app, key)?.bool ?? false })
        }
        var result: [SettingsSection] = []
        if let tab = spec.tab {
            let option = tabOption(tab, title: spec.title)
            if power == nil {
                // Страница вкладки: её главный переключатель - есть ли вкладка в острове.
                power = PagePower(option: option, isOn: { [model, app] in
                    (model.value(app, "tabs")?.strings ?? []).contains(tab)
                })
            } else {
                result.append(SettingsSection(id: "\(app).\(spec.id).tab", options: [option]))
            }
        }
        result += sections(spec.sections, byKey: byKey, used: &used, page: spec.id)
        // Параметры вкладки или функции - её группами из схемы, без повторения её названия в заголовках.
        let groups = groupsByID[spec.id] ?? []
        let prefix = Self.commonPrefix(groups)
        var advanced: [SettingsOption] = []
        for group in groups {
            let fields = group.fields.filter { !used.contains($0.key) && !style.isHidden($0.key) }
            used.formUnion(fields.map(\.key))
            advanced += fields.filter { style.advanced.contains($0.key) }.compactMap(option)
            let options = fields.filter { !style.advanced.contains($0.key) }.compactMap(option)
            guard !options.isEmpty else { continue }
            var title: String? = String(group.title.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if title?.isEmpty == true || groups.count == 1 { title = nil }
            result.append(SettingsSection(id: "\(app).\(spec.id).\(group.title)", title: title, footer: group.footer,
                                          options: options))
        }
        if !advanced.isEmpty {
            result.append(SettingsSection(id: "\(app).\(spec.id).advanced", title: "Тонкая настройка",
                                          options: advanced, collapsed: true))
        }
        let children = spec.children.map { page(for: $0, groupsByID: groupsByID, byKey: byKey, used: &used) }
        return SettingsPage(
            id: "\(app).page.\(spec.id)", title: spec.title, symbol: spec.symbol, tint: spec.tint,
            subtitle: spec.subtitle, power: power, sections: result,
            subgroups: children.isEmpty ? [] : [PageGroup(id: "\(app).\(spec.id).children", pages: children)]
        )
    }

    /// Секции из раскладки: видимые поля и свёрнутая «тонкая настройка» к каждой секции.
    private func sections(_ layout: [ModuleStyle.SectionLayout], byKey: [String: SuiteSchema.Field],
                          used: inout Set<String>, page: String = "root") -> [SettingsSection] {
        var result: [SettingsSection] = []
        var advanced: [SettingsOption] = []
        for section in layout {
            let fields = section.keys.compactMap { byKey[$0] }.filter { !used.contains($0.key) }
            used.formUnion(fields.map(\.key))
            advanced += fields.filter { style.advanced.contains($0.key) }.compactMap(option)
            let options = fields.filter { !style.advanced.contains($0.key) }.compactMap(option)
            if !options.isEmpty {
                result.append(SettingsSection(id: "\(app).\(page).\(section.title)", title: section.title,
                                              footer: section.footer, options: options))
            }
        }
        if !advanced.isEmpty {
            result.append(SettingsSection(id: "\(app).\(page).advanced", title: "Тонкая настройка",
                                          options: advanced, collapsed: true))
        }
        return result
    }

    private func option(_ field: SuiteSchema.Field) -> SettingsOption? { option(field, title: nil) }

    private func option(_ field: SuiteSchema.Field, title: String?) -> SettingsOption? {
        guard model.isVisible(field, in: app) else { return nil }
        var copy = style.copy(for: field)
        if let title { copy.title = title }
        return SettingsOption(
            id: "\(app).\(field.key)",
            title: copy.title,
            keywords: [field.title, copy.help ?? "", field.help ?? ""] + (field.options ?? []).map(\.title),
            fullWidth: field.kind == .list
        ) { [model, app] in
            FieldRow(model: model, app: app, field: field, copy: copy)
        }
    }

    /// Переключатель «вкладка есть в острове»: правит список `tabs`.
    private func tabOption(_ tab: String, title: String) -> SettingsOption {
        SettingsOption(id: "\(app).tab.\(tab)", title: "Вкладка «\(title)»", keywords: ["вкладка", "показывать"]) {
            [model, app] in
            TabToggle(model: model, app: app, tab: tab, title: title)
        }
    }

    /// `moduleOptions.<id>.<ключ>` → id; у общих настроек - nil.
    static func optionID(_ key: String) -> String? {
        let parts = key.split(separator: ".")
        guard parts.count >= 3, parts[0] == "moduleOptions" else { return nil }
        return String(parts[1])
    }

    /// Общее начало названий групп одной функции, до последнего «: » («Текст песни: »).
    static func commonPrefix(_ groups: [SuiteSchema.Group]) -> String {
        guard groups.count > 1, var prefix = groups.first?.title else { return "" }
        for group in groups.dropFirst() {
            while !group.title.hasPrefix(prefix) { prefix.removeLast() }
        }
        guard let range = prefix.range(of: ": ", options: .backwards) else { return "" }
        return String(prefix[..<range.upperBound])
    }

    /// Название функции по её группам: общее начало без «: » или название единственной группы.
    static func title(of groups: [SuiteSchema.Group]) -> String {
        let prefix = commonPrefix(groups)
        if !prefix.isEmpty { return String(prefix.dropLast(2)) }
        return groups.first?.title ?? "Без названия"
    }
}

/// Строка «Вкладка «Музыка»» на странице вкладки: включает и выключает её в острове.
private struct TabToggle: View {
    let model: HubModel
    let app: String
    let tab: String
    let title: String

    var body: some View {
        let tabs = model.value(app, "tabs")?.strings ?? []
        Toggle(isOn: Binding(
            get: { tabs.contains(tab) },
            set: { on in
                let list = on ? tabs + [tab] : tabs.filter { $0 != tab }
                guard !list.isEmpty else { return }
                withMotion(Motion.spring) { model.set(app, "tabs", .array(list.map { .string($0) })) }
            }
        )) {
            Text("Вкладка в острове")
            Text(tabs.contains(tab) ? "Видна среди вкладок раскрытого острова" : "Сейчас скрыта")
        }
        .toggleStyle(GlassSwitch())
        .controlSize(ControlMetrics.switchSize)
    }
}
