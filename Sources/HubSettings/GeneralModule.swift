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
    var summary: String { "Какие приложения набора работают." }
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

}

/// Настройки самого окна (не приложений набора) - в UserDefaults хаба.
enum HubPreferences {
    /// Показывать технические секции («Тонкая настройка»).
    static let showAdvanced = "showAdvanced"
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
        .toggleStyle(GlassSwitch())
        .controlSize(ControlMetrics.switchSize)
        .disabled(power?.available != true || power?.isBusy == true)
    }
}
