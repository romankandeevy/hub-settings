import AppKit
import SuiteKit
import SwiftUI

/// Секции Flow, которые не укладываются в поля схемы: список замен, папки на диске и разрешения.
/// Стоят среди секций схемы: `after` - после какой из них.
@MainActor
enum ModuleExtras {
    struct Extra {
        let after: String?
        let section: SettingsSection
    }

    static func sections(for app: String, model: HubModel) -> [Extra] {
        guard app == "flow" else { return [] }
        return [
            Extra(after: "Чистка текста", section: SettingsSection(
                id: "flow.replacements",
                title: "Замены",
                footer: "По целым словам, без учёта регистра. Например, «флоу локал» → «Flow Local».",
                options: [
                    SettingsOption(id: "flow.replacements", title: "Замены",
                                   keywords: ["было", "стало", "имена", "бренды", "слова"], fullWidth: true) {
                        ReplacementsEditor(model: model, app: app, key: "replacements")
                    },
                ]
            )),
            Extra(after: "История", section: SettingsSection(id: "flow.files", title: "Файлы", options: [
                SettingsOption(id: "flow.recordings", title: "Папка записей", keywords: ["звук", "wav", "finder"]) {
                    LabeledContent {
                        Button("Показать в Finder") { reveal(FlowPaths.recordings) }
                    } label: {
                        Text("Папка записей")
                        Text(FlowPaths.recordingsSummary())
                    }
                },
                SettingsOption(id: "flow.log", title: "Журнал", keywords: ["лог", "ошибки"]) {
                    LabeledContent {
                        Button("Показать журнал") { NSWorkspace.shared.open(FlowPaths.log) }
                    } label: {
                        Text("Журнал")
                        Text("~/Library/Logs/FlowLocal.log")
                    }
                },
            ], collapsed: true)),
            Extra(after: nil, section: SettingsSection(
                id: "flow.permissions",
                title: "Разрешения",
                footer: "Если Flow уже есть в списке, а доступ не работает, удалите его из списка и добавьте снова.",
                options: [
                    SettingsOption(id: "flow.micAccess", title: "Микрофон", keywords: ["доступ", "разрешение"]) {
                        LabeledContent {
                            Button("Открыть") { openPrivacy("Privacy_Microphone") }
                        } label: {
                            Text("Микрофон")
                            Text("Без него диктовка выключена")
                        }
                    },
                    SettingsOption(id: "flow.axAccess", title: "Универсальный доступ",
                                   keywords: ["доступ", "разрешение", "вставка", "accessibility"]) {
                        LabeledContent {
                            Button("Открыть") { openPrivacy("Privacy_Accessibility") }
                        } label: {
                            Text("Универсальный доступ")
                            Text("Без него текст остаётся в буфере обмена")
                        }
                    },
                ]
            )),
        ]
    }

    private static func reveal(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    private static func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Где Flow держит файлы (как `Paths` во Flow).
private enum FlowPaths {
    static let recordings = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/FlowLocal/Recordings", isDirectory: true)
    static let log = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/FlowLocal.log")

    /// «12 файлов · 24 МБ».
    static func recordingsSummary() -> String {
        let files = (try? FileManager.default.contentsOfDirectory(at: recordings,
                                                                 includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let wav = files.filter { $0.pathExtension == "wav" }
        let bytes = wav.reduce(Int64(0)) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        let count = wav.count
        let word = count % 10 == 1 && count % 100 != 11 ? "файл"
            : (2...4).contains(count % 10) && !(12...14).contains(count % 100) ? "файла" : "файлов"
        return "\(count) \(word) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }
}

// MARK: - замены

/// Пары «было → стало». Хранятся в UserDefaults Flow массивом пар строк. В файл пишется, когда уходите
/// из поля или жмёте Return, - не на каждую букву. Пустые пары не сохраняются.
private struct ReplacementsEditor: View {
    let model: HubModel
    let app: String
    let key: String
    @State private var rows: [Row] = []
    @FocusState private var focused: Field?

    /// Поле в фокусе: строка и половина («было» или «стало»).
    struct Field: Hashable {
        let row: UUID
        let to: Bool
    }

    struct Row: Identifiable, Equatable {
        let id = UUID()
        var from: String
        var to: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach($rows) { $row in
                HStack(spacing: Spacing.md) {
                    TextField("", text: $row.from, prompt: Text("Было"))
                        .focused($focused, equals: Field(row: row.id, to: false))
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    TextField("", text: $row.to, prompt: Text("Стало"))
                        .focused($focused, equals: Field(row: row.id, to: true))
                    Button {
                        withMotion { rows.removeAll { $0.id == row.id } }
                        save()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Удалить замену")
                    .accessibilityLabel("Удалить замену")
                }
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            }
            Button {
                let row = Row(from: "", to: "")
                withMotion { rows.append(row) }
                focused = Field(row: row.id, to: false)
            } label: {
                Label("Добавить замену", systemImage: "plus")
            }
        }
        .padding(.vertical, Spacing.xs)
        .onAppear(perform: load)
        .onChange(of: stored) { if focused == nil { load() } }
        .onChange(of: focused) { save() }
    }

    private var stored: [[String]] {
        guard case let .array(list)? = model.value(app, key) else { return [] }
        return list.compactMap { pair in
            guard let items = pair.strings, items.count == 2 else { return nil }
            return items
        }
    }

    private func load() {
        let pairs = stored
        guard pairs != rows.map({ [$0.from, $0.to] }) else { return }
        rows = pairs.map { Row(from: $0[0], to: $0[1]) }
    }

    private func save() {
        let pairs = rows
            .map { [$0.from.trimmingCharacters(in: .whitespaces), $0.to.trimmingCharacters(in: .whitespaces)] }
            .filter { !$0[0].isEmpty }
        guard pairs != stored else { return }
        model.set(app, key, .array(pairs.map { .array($0.map { .string($0) }) }))
    }
}
