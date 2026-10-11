import SwiftUI

// Единый протокол модуля настроек. Окно ничего не знает о конкретных модулях: оно берёт список из
// `ModuleRegistry` и по протоколу строит боковой список, поиск и экран модуля. Поэтому все модули
// выглядят одинаково: шапка, (превью), секции с опциями, «Сбросить настройки модуля».

/// Где модуль стоит в боковом списке.
enum ModuleGroup: Int, CaseIterable {
    /// Общие настройки хаба - отдельно сверху.
    case hub
    /// Приложения набора.
    case modules
}

@MainActor
protocol SettingsModule {
    /// Уникальный идентификатор; он же запоминается как последний открытый модуль.
    var id: String { get }
    var title: String { get }
    /// Одна строка: что модуль делает.
    var summary: String { get }
    var symbol: String { get }
    var tint: Color { get }
    var group: ModuleGroup { get }
    /// Главный переключатель «Включено» в шапке. nil - у модуля его нет.
    var power: ModulePower? { get }
    var sections: [SettingsSection] { get }
    /// Подстраницы: строки со значком и стрелкой под секциями главной страницы, как в Системных настройках.
    /// Большой модуль делится на них, чтобы одна страница не была простынёй из сотен строк.
    var pageGroups: [PageGroup] { get }
    /// Можно ли сейчас сбросить (что-то отличается от стандартного).
    var canReset: Bool { get }
    /// nil - у модуля нет кнопки сброса.
    var reset: (() -> Void)? { get }
}

extension SettingsModule {
    var group: ModuleGroup { .modules }
    var power: ModulePower? { nil }
    var pageGroups: [PageGroup] { [] }
    var canReset: Bool { false }
    var reset: (() -> Void)? { nil }

    /// Все опции модуля с их местом (страница и секция) - для поиска и перехода к строке.
    var allOptions: [OptionPlace] {
        var result = sections.flatMap { section in section.options.map { OptionPlace(pages: [], section: section, option: $0) } }
        func walk(_ page: SettingsPage, _ trail: [SettingsPage]) {
            let path = trail + [page]
            if let power = page.power { result.append(OptionPlace(pages: path, section: nil, option: power.option)) }
            for section in page.sections {
                result += section.options.map { OptionPlace(pages: path, section: section, option: $0) }
            }
            for group in page.subgroups { for child in group.pages { walk(child, path) } }
        }
        for group in pageGroups { for page in group.pages { walk(page, []) } }
        return result
    }

    /// Страница по идентификатору (в том числе вложенная).
    func page(_ id: String) -> SettingsPage? {
        func find(_ groups: [PageGroup]) -> SettingsPage? {
            for group in groups {
                for page in group.pages {
                    if page.id == id { return page }
                    if let found = find(page.subgroups) { return found }
                }
            }
            return nil
        }
        return find(pageGroups)
    }
}

/// Где лежит опция: цепочка страниц от главной (пустая - на главной) и секция.
struct OptionPlace {
    let pages: [SettingsPage]
    let section: SettingsSection?
    let option: SettingsOption

    /// «Музыка › Текст песни» - для строки результата поиска.
    func path(module: String) -> String {
        var parts = [module] + pages.map(\.title)
        if let title = section?.title, title != parts.last { parts.append(title) }
        return parts.joined(separator: " › ")
    }
}

/// Группа строк-подстраниц - одна секция формы.
struct PageGroup: Identifiable {
    let id: String
    var title: String?
    var footer: String?
    var pages: [SettingsPage]
}

/// Подстраница модуля: строка со значком в цветной плитке, по нажатию - своя форма.
struct SettingsPage: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
    /// Вторая строка под названием: что на странице.
    var subtitle: String?
    /// Главный переключатель страницы (вкладка показана, функция включена): строка вверху страницы,
    /// остальное приглушено, пока он выключен. Его же состояние видно справа в строке («Вкл.» / «Выкл.»).
    var power: PagePower?
    var sections: [SettingsSection] = []
    /// Вложенные подстраницы (например, у «Музыки» - текст песни и эквалайзер).
    var subgroups: [PageGroup] = []
}

struct PagePower {
    let option: SettingsOption
    let isOn: @MainActor () -> Bool
}

/// Главный переключатель модуля и его состояние для бокового списка.
struct ModulePower {
    var isOn: Bool
    /// Пока переключается (приложение запускается или закрывается).
    var isBusy = false
    /// Пояснение под переключателем, если модуль нельзя включить.
    var note: String?
    var available = true
    let set: (Bool) -> Void
}

struct SettingsSection: Identifiable {
    let id: String
    var title: String?
    /// Пояснение под секцией - там, где без него непонятно.
    var footer: String?
    var options: [SettingsOption]
    /// Свёрнута, пока её не раскроют: технические настройки, которые почти никому не нужны.
    var collapsed = false
}

/// Одна опция: строка в форме. Её находит поиск, к ней прокручивается и её подсвечивает окно.
struct SettingsOption: Identifiable {
    /// Уникален среди всех модулей: «island.openWidth».
    let id: String
    let title: String
    /// Что ещё ищет поиск: пояснение, варианты выбора, синонимы.
    var keywords: [String] = []
    /// Опция занимает всю секцию сама (список с перетаскиванием) - окно не рисует у неё подпись.
    var fullWidth = false
    let row: @MainActor () -> AnyView

    init(id: String, title: String, keywords: [String] = [], fullWidth: Bool = false,
         @ViewBuilder row: @escaping @MainActor () -> some View) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.fullWidth = fullWidth
        self.row = { AnyView(row()) }
    }
}

/// Все модули окна по порядку: сначала общие настройки хаба, потом приложения набора.
/// Новый модуль появляется в боковом списке и в поиске сам: приложение публикует схему настроек
/// (`SuiteSchema`), и `SchemaModule` превращает её в модуль. Для модуля, у которого нет схемы,
/// достаточно реализовать `SettingsModule` и добавить его в `custom`. Установленное приложение набора без схемы
/// тоже появится само (`AppOnlyModule`): его можно включать и выключать.
@MainActor
struct ModuleRegistry {
    let model: HubModel
    let apps: AppMonitor

    var modules: [any SettingsModule] {
        let custom: [any SettingsModule] = [GeneralModule(model: model, apps: apps)]
        let all = custom + appModules
        return ModuleGroup.allCases.flatMap { group in all.filter { $0.group == group } }
    }

    /// Приложения набора: со схемой - полный экран настроек, без схемы - только «Включено». По названию.
    var appModules: [any SettingsModule] {
        let schemas: [any SettingsModule] = model.schemas.filter { !Self.excluded.contains($0.app) }.map { SchemaModule(schema: $0, model: model, apps: apps) }
        let known = Set(model.schemas.map(\.app))
        let plain: [any SettingsModule] = apps.installed.filter { !known.contains($0.id) }
            .filter { !Self.excluded.contains($0.id) }
            .map { AppOnlyModule(app: $0, apps: apps) }
        func rank(_ module: any SettingsModule) -> Int { Self.order.firstIndex(of: module.id) ?? Self.order.count }
        return (schemas + plain).sorted {
            (rank($0), $0.title.localizedLowercase) < (rank($1), $1.title.localizedLowercase)
        }
    }

    /// Порядок вкладок; остальные - за ними по названию.
    static let order = ["island", "flow", "shelf", "awake"]
    /// Есть в наборе, но в хабе не показываются.
    static let excluded: Set<String> = ["sidebar"]

    func module(_ id: String?) -> (any SettingsModule)? {
        let all = modules
        return all.first { $0.id == id } ?? all.first
    }
}
