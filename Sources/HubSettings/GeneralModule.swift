import AppKit
import SuiteKit
import SwiftUI

/// Настройки самого хаба - первый пункт бокового списка, отдельно от модулей.
struct GeneralModule: SettingsModule {
    let model: HubModel
    let apps: AppMonitor

    static let moduleID = "general"

    var id: String { Self.moduleID }
    var title: String { "Основные" }
    var summary: String { "Какие модули работают и как выглядит это окно." }
    var symbol: String { "gearshape.fill" }
    var tint: Color { TileColor.gray }
    var group: ModuleGroup { .hub }

    var sections: [SettingsSection] {
        let modules = ModuleRegistry(model: model, apps: apps).appModules
        return [
            SettingsSection(
                id: "general.modules",
                title: "Модули",
                footer: modules.isEmpty
                    ? "Модули появляются здесь, когда их приложение установлено."
                    : "Выключенный модуль закрывается и не работает, пока вы снова его не включите.",
                options: modules.map { module in
                    SettingsOption(id: "general.module.\(module.id)", title: module.title,
                                   keywords: [module.summary, "включить", "выключить", "запустить"]) {
                        ModuleSwitchRow(module: module)
                    }
                }
            ),
            SettingsSection(id: "general.window", title: "Окно", options: [
                SettingsOption(id: "general.sidebarStatus", title: "Отмечать выключенные модули в списке",
                               keywords: ["статус", "боковой список"]) {
                    HubPreferenceToggle(title: "Отмечать выключенные модули в списке",
                                        help: "Рядом с названием появится «Выкл.»")
                },
            ]),
            SettingsSection(
                id: "general.files",
                title: "Файлы настроек",
                footer: "Настройки хранятся в обычных файлах. Хаб и приложения меняют их на лету.",
                options: [
                    SettingsOption(id: "general.folder", title: "Папка настроек",
                                   keywords: ["finder", "файл", "json"]) {
                        LabeledContent("Папка настроек") {
                            Button("Показать в Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([SuitePaths.root])
                            }
                        }
                    },
                ]
            ),
        ]
    }

    var canReset: Bool {
        UserDefaults.standard.object(forKey: HubPreferences.showStatus) != nil
    }

    var reset: (() -> Void)? {
        { UserDefaults.standard.removeObject(forKey: HubPreferences.showStatus) }
    }
}

/// Настройки самого окна (не приложений набора) - в UserDefaults хаба.
enum HubPreferences {
    static let showStatus = "showModuleStatus"
    static let showStatusDefault = true
}

private struct HubPreferenceToggle: View {
    let title: String
    let help: String
    @AppStorage(HubPreferences.showStatus) private var value = HubPreferences.showStatusDefault

    var body: some View {
        Toggle(isOn: $value) {
            Text(title)
            Text(help)
        }
        .toggleStyle(.switch)
        .controlSize(ControlMetrics.switchSize)
    }
}

/// Строка модуля: плитка, название, описание и переключатель «включён».
private struct ModuleSwitchRow: View {
    let module: any SettingsModule

    var body: some View {
        let power = module.power
        Toggle(isOn: Binding(get: { power?.isOn ?? false }, set: { power?.set($0) })) {
            HStack(spacing: Spacing.tileLabel) {
                ModuleTile(symbol: module.symbol, tint: module.tint, size: TileMetrics.row)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(module.title)
                    Text(power?.available == false ? (power?.note ?? "") : module.summary)
                        .font(TextStyle.searchResultPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(ControlMetrics.switchSize)
        .disabled(power?.available != true || power?.isBusy == true)
    }
}
