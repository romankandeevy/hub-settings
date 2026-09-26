import AppKit
import SwiftUI

// Окно как Системные настройки: слева список (сверху поиск, потом «Основные», потом модули),
// справа экран выбранного модуля. Всё применяется сразу, без «Сохранить»; ⌘Z отменяет.
struct HubView: View {
    let model: HubModel
    let apps: AppMonitor
    @State private var query = ""
    /// Настройка, которую надо показать и подсветить (выбрали в поиске или потянули ручку в превью).
    @State private var highlight: String?

    var body: some View {
        let registry = ModuleRegistry(model: model, apps: apps)
        let current = registry.module(model.selection)
        NavigationSplitView {
            ModuleSidebar(modules: registry.modules, query: query, selection: Binding(
                get: { current?.id },
                set: { id in if let id { model.selection = id } }
            )) { module, option in
                model.selection = module
                highlight = option
            }
            .navigationSplitViewColumnWidth(min: WindowMetrics.sidebarMin, ideal: WindowMetrics.sidebarIdeal,
                                            max: WindowMetrics.sidebarMax)
            .searchable(text: $query, placement: .sidebar, prompt: "Поиск")
        } detail: {
            ZStack {
                if let current {
                    ModuleScreen(module: current, model: model, highlight: $highlight)
                        .id(current.id)
                        .transition(.opacity)
                }
            }
            .motion(Motion.page, value: current?.id)
            .onChange(of: model.pendingTarget) { _, target in
                guard let target else { return }
                model.pendingTarget = nil
                highlight = target
            }
            .navigationSplitViewColumnWidth(min: WindowMetrics.detailMin, ideal: WindowMetrics.detailMin)
        }
    }
}

// MARK: - плитка

/// Белый символ в цветном скруглённом квадрате - значок модуля.
struct ModuleTile: View {
    let symbol: String
    let tint: Color
    let size: TileMetrics.Size

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size.symbol, weight: .medium))
            .foregroundStyle(Palette.tileSymbol)
            .frame(width: size.side, height: size.side)
            .background(tint.gradient, in: shape)
            .overlay { shape.strokeBorder(Palette.tileStroke, lineWidth: 0.5) }
            .accessibilityHidden(true)
    }
}

// MARK: - боковой список

private struct ModuleSidebar: View {
    let modules: [any SettingsModule]
    let query: String
    @Binding var selection: String?
    let open: (_ module: String, _ option: String?) -> Void
    @AppStorage(HubPreferences.showStatus) private var showStatus = HubPreferences.showStatusDefault
    @State private var pickedResult: String?

    var body: some View {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = text.isEmpty ? [] : SearchIndex(modules: modules).search(text)
        // Один и тот же список для модулей и для результатов поиска: так поле поиска не теряет фокус при вводе.
        List(selection: Binding(
            get: { text.isEmpty ? selection : pickedResult },
            set: { id in
                if text.isEmpty { selection = id; return }
                pickedResult = id
                guard let id, let hit = results.flatMap(\.hits).first(where: { $0.id == id }) else { return }
                open(hit.moduleID, hit.target)
            }
        )) {
            if text.isEmpty {
                ForEach(ModuleGroup.allCases, id: \.self) { group in
                    let items = modules.filter { $0.group == group }
                    if !items.isEmpty {
                        Section {
                            ForEach(items, id: \.id) { module in
                                SidebarRow(module: module, showStatus: showStatus).tag(module.id)
                            }
                        }
                    }
                }
            } else {
                ForEach(results, id: \.module.id) { result in
                    Section(result.module.title) {
                        ForEach(result.hits) { hit in
                            SearchRow(module: result.module, hit: hit).tag(hit.id)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if !text.isEmpty, results.isEmpty {
                ContentUnavailableView.search(text: text)
            }
        }
        .onChange(of: text) { pickedResult = nil }
    }
}

private struct SidebarRow: View {
    let module: any SettingsModule
    let showStatus: Bool

    var body: some View {
        HStack(spacing: Spacing.tileLabel) {
            ModuleTile(symbol: module.symbol, tint: module.tint, size: TileMetrics.sidebar)
            Text(module.title)
                .lineLimit(1)
            Spacer(minLength: 0)
            if showStatus, let power = module.power, power.available, !power.isOn {
                Text("Выкл.")
                    .font(TextStyle.sidebarStatus)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SearchRow: View {
    let module: any SettingsModule
    let hit: SearchIndex.Hit

    var body: some View {
        HStack(spacing: Spacing.tileLabel) {
            ModuleTile(symbol: module.symbol, tint: module.tint, size: TileMetrics.sidebar)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(hit.title)
                    .font(TextStyle.searchResultTitle)
                    .lineLimit(2)
                if let path = hit.path {
                    Text(path)
                        .font(TextStyle.searchResultPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - поиск

/// Поиск по названиям модулей, подстраниц и всех опций (подпись, пояснение, варианты выбора, название секции).
@MainActor
struct SearchIndex {
    let modules: [any SettingsModule]

    struct Hit: Identifiable {
        let moduleID: String
        /// Куда перейти: id опции или «page:<id>» для подстраницы; nil - сам модуль.
        let target: String?
        let title: String
        let path: String?
        let rank: Int
        var id: String { target ?? "module.\(moduleID)" }
    }

    struct Result {
        let module: any SettingsModule
        let hits: [Hit]
    }

    func search(_ query: String) -> [Result] {
        let words = query.split(separator: " ").map(String.init)
        func matches(_ text: String) -> Bool { words.allSatisfy { text.localizedStandardContains($0) } }

        var results: [Result] = []
        for module in modules {
            var hits: [Hit] = []
            if matches(module.title) || matches(module.summary) {
                hits.append(Hit(moduleID: module.id, target: nil, title: module.title, path: nil, rank: 0))
            }
            @MainActor func pages(_ groups: [PageGroup], trail: [String]) {
                for group in groups {
                    for page in group.pages {
                        if matches(page.title) || matches(page.subtitle ?? "") {
                            hits.append(Hit(moduleID: module.id, target: ModuleScreen.pageTarget(page.id), title: page.title,
                                            path: ([module.title] + trail).joined(separator: " › "), rank: 1))
                        }
                        pages(page.subgroups, trail: trail + [page.title])
                    }
                }
            }
            pages(module.pageGroups, trail: [])
            for place in module.allOptions {
                let option = place.option
                let rank: Int
                if matches(option.title) { rank = 1 }
                else if matches(([place.section?.title ?? ""] + place.pages.map(\.title) + option.keywords).joined(separator: " ")) { rank = 2 }
                else { continue }
                hits.append(Hit(moduleID: module.id, target: option.id, title: option.title,
                                path: place.path(module: module.title), rank: rank))
            }
            if !hits.isEmpty { results.append(Result(module: module, hits: hits.sorted { $0.rank < $1.rank })) }
        }
        return results
    }
}

// MARK: - экран модуля

/// Экран модуля: шапка с плиткой, описанием и «Включено», превью, секции опций, строки подстраниц, внизу сброс.
/// Подстраницы открываются в том же окне со стрелкой «назад», как в Системных настройках.
/// Выключенный модуль виден, но его настройки приглушены и не нажимаются.
struct ModuleScreen: View {
    let module: any SettingsModule
    let model: HubModel
    @Binding var highlight: String?
    @State private var flashing: String?
    @State private var confirmReset = false
    @State private var path: [String] = []

    static func pageTarget(_ id: String) -> String { "page:" + id }

    private func open(_ id: String) {
        withMotion(Motion.page) { path.append(id) }
    }

    var body: some View {
        let power = module.power
        let active = power.map { $0.isOn || !$0.available } ?? true
        let page = path.last.flatMap { module.page($0) }
        ZStack {
            // Главная страница остаётся в дереве под подстраницей: возвращаясь, попадаешь на то же место прокрутки.
            Form {
                Section {
                    ModuleHeader(module: module)
                    if let power, power.available {
                        PowerRow(power: power)
                    }
                } footer: {
                    if let note = power?.note { Footer(text: note) }
                }

                if let preview = module.preview {
                    Section {
                        preview
                            .frame(height: ControlMetrics.previewHeight)
                            .clipShape(RoundedRectangle(cornerRadius: ControlMetrics.previewRadius, style: .continuous))
                    }
                    .inactive(!active)
                }

                OptionSections(sections: module.sections, flashing: flashing)
                    .inactive(!active)

                PageLinks(groups: module.pageGroups, open: open)
                    .inactive(!active)

                if module.reset != nil {
                    Section {
                        HStack {
                            Spacer()
                            ResetButton(module: module) { confirmReset = true }
                        }
                    } footer: {
                        Footer(text: "Все настройки модуля, на всех его страницах, вернутся к стандартным значениям.")
                    }
                }
            }
            .formStyle(.grouped)
            .opacity(page == nil ? 1 : 0)
            .allowsHitTesting(page == nil)
            .accessibilityHidden(page != nil)

            if let page {
                PageScreen(page: page, flashing: flashing, open: open)
                    .inactive(!active)
                    .background(.background)
                    .id(page.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
            }
        }
        .clipped()
        .navigationTitle(page?.title ?? module.title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withMotion(Motion.page) { _ = path.popLast() }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Назад")
                .disabled(path.isEmpty)
                .keyboardShortcut("[", modifiers: .command)
            }
        }
        .onAppear { reveal(highlight) }
        .onChange(of: highlight) { _, id in reveal(id) }
        // Потянули ручку в превью - форма показывает поле, которое она меняет.
        .onChange(of: model.focusKey) { _, key in
            guard let key else { return }
            model.focusKey = nil
            highlight = "\(module.id).\(key)"
        }
        .confirmationDialog("Сбросить настройки «\(module.title)»?", isPresented: $confirmReset) {
            Button("Сбросить", role: .destructive) { withMotion(Motion.spring) { module.reset?() } }
        } message: {
            Text("Все настройки модуля вернутся к стандартным значениям. Для приложений набора сброс можно отменить через ⌘Z.")
        }
    }

    /// Показать строку (или подстраницу): открыть нужную страницу, прокрутить к строке и подсветить её.
    private func reveal(_ target: String?) {
        guard let target else { return }
        highlight = nil
        if target.hasPrefix("page:") {
            let id = String(target.dropFirst(5))
            if let trail = trail(to: id) { withMotion(Motion.page) { path = trail } }
            return
        }
        guard let place = module.allOptions.first(where: { $0.option.id == target }) else { return }
        let pages = place.pages.map(\.id)
        let moved = pages != path
        withMotion(Motion.page) { path = pages }
        Task { @MainActor in
            // Даём странице открыться и форме разложиться, потом прокручиваем и подсвечиваем строку.
            try? await Task.sleep(for: .milliseconds(moved ? 420 : 120))
            RowAnchor.scroll(to: target)
            withMotion(Motion.fast) { flashing = target }
            try? await Task.sleep(for: Motion.highlightDuration)
            if flashing == target { withMotion(Motion.highlightFade) { flashing = nil } }
        }
    }

    /// Цепочка страниц от главной до страницы `id`.
    private func trail(to id: String) -> [String]? {
        func walk(_ groups: [PageGroup], _ trail: [String]) -> [String]? {
            for group in groups {
                for page in group.pages {
                    if page.id == id { return trail + [page.id] }
                    if let found = walk(page.subgroups, trail + [page.id]) { return found }
                }
            }
            return nil
        }
        return walk(module.pageGroups, [])
    }
}

/// Кнопка сброса - отдельной вьюхой: «есть ли что сбрасывать» зависит от всего файла настроек,
/// и пусть на каждую правку пересчитывается только она, а не весь экран.
private struct ResetButton: View {
    let module: any SettingsModule
    let action: () -> Void

    var body: some View {
        Button("Сбросить настройки модуля…", action: action)
            .disabled(!module.canReset)
    }
}

/// Подстраница: главный переключатель (если есть), секции опций, вложенные подстраницы.
private struct PageScreen: View {
    let page: SettingsPage
    let flashing: String?
    let open: (String) -> Void

    var body: some View {
        let on = page.power?.isOn() ?? true
        Form {
            Section {
                PageHeader(page: page)
                if let power = page.power {
                    OptionRow(option: power.option, flashing: flashing)
                }
            }
            OptionSections(sections: page.sections, flashing: flashing)
                .inactive(!on)
            PageLinks(groups: page.subgroups, open: open)
                .inactive(!on)
        }
        .formStyle(.grouped)
    }
}

private struct PageHeader: View {
    let page: SettingsPage

    var body: some View {
        HStack(spacing: Spacing.headerTile) {
            ModuleTile(symbol: page.symbol, tint: page.tint, size: TileMetrics.pageHeader)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(page.title)
                    .font(TextStyle.pageTitle)
                if let subtitle = page.subtitle {
                    Text(subtitle)
                        .font(TextStyle.headerSummary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Секции опций. Технические настройки секции («Тонкая настройка») свёрнуты и не рисуются, пока их не раскрыли.
private struct OptionSections: View {
    let sections: [SettingsSection]
    let flashing: String?

    var body: some View {
        ForEach(sections) { section in
            if section.collapsed {
                CollapsedSection(section: section, flashing: flashing)
            } else {
                Section {
                    ForEach(section.options) { option in
                        OptionRow(option: option, flashing: flashing)
                    }
                } header: {
                    if let title = section.title { Text(title) }
                } footer: {
                    if let footer = section.footer { Footer(text: footer) }
                }
            }
        }
    }
}

private struct CollapsedSection: View {
    let section: SettingsSection
    let flashing: String?
    @State private var expanded = false

    var body: some View {
        Section(isExpanded: Binding(get: { expanded || section.options.contains { $0.id == flashing } },
                                    set: { value in withMotion(Motion.spring) { expanded = value } })) {
            ForEach(section.options) { option in
                OptionRow(option: option, flashing: flashing)
            }
        } header: {
            Text(section.title ?? "Тонкая настройка")
        }
    }
}

private struct OptionRow: View {
    let option: SettingsOption
    let flashing: String?

    var body: some View {
        option.row()
            .id(option.id)
            .background(RowAnchor(id: option.id))
            .background { Highlight(on: flashing == option.id) }
    }
}

/// Строки подстраниц: значок в цветной плитке, название, пояснение, справа «Вкл.»/«Выкл.» и стрелка.
private struct PageLinks: View {
    let groups: [PageGroup]
    let open: (String) -> Void

    var body: some View {
        ForEach(groups) { group in
            Section {
                ForEach(group.pages) { page in
                    Button { open(page.id) } label: {
                        PageLinkRow(page: page)
                    }
                    .buttonStyle(PageLinkStyle())
                    .background(RowAnchor(id: ModuleScreen.pageTarget(page.id)))
                }
            } header: {
                if let title = group.title { Text(title) }
            } footer: {
                if let footer = group.footer { Footer(text: footer) }
            }
        }
    }
}

private struct PageLinkRow: View {
    let page: SettingsPage

    var body: some View {
        HStack(spacing: Spacing.tileLabel) {
            ModuleTile(symbol: page.symbol, tint: page.tint, size: TileMetrics.row)
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title)
                if let subtitle = page.subtitle {
                    Text(subtitle)
                        .font(TextStyle.searchResultPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.md)
            if let power = page.power {
                Text(power.isOn() ? "Вкл." : "Выкл.")
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(TextStyle.chevron)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Строка-кнопка на всю ширину: под курсором и при нажатии чуть подсвечивается, как строки Системных настроек.
private struct PageLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PageLinkBody(configuration: configuration)
    }
}

private struct PageLinkBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false

    var body: some View {
        configuration.label
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: ControlMetrics.previewRadius / 2, style: .continuous)
                    .fill(configuration.isPressed ? Palette.rowPressed : hovering ? Palette.rowHover : .clear)
                    .padding(.horizontal, -Spacing.sm)
                    .padding(.vertical, -Spacing.xs)
            }
            .onHover { hovering = $0 }
            .animation(Motion.fast, value: hovering)
    }
}

private struct ModuleHeader: View {
    let module: any SettingsModule

    var body: some View {
        HStack(spacing: Spacing.headerTile) {
            ModuleTile(symbol: module.symbol, tint: module.tint, size: TileMetrics.header)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(module.title)
                    .font(TextStyle.headerTitle)
                if !module.summary.isEmpty {
                    Text(module.summary)
                        .font(TextStyle.headerSummary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.headerVertical)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct PowerRow: View {
    let power: ModulePower

    var body: some View {
        HStack(spacing: Spacing.md) {
            Toggle("Включено", isOn: Binding(get: { power.isOn }, set: { power.set($0) }))
                .toggleStyle(.switch)
                .controlSize(ControlMetrics.switchSize)
                .disabled(power.isBusy)
            if power.isBusy {
                ProgressView().controlSize(.small)
            }
        }
    }
}

private struct Footer: View {
    let text: String

    var body: some View {
        Text(text)
            .font(TextStyle.footer)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Подсветка найденной строки: мягкая акцентная подложка, которая гаснет сама.
private struct Highlight: View {
    let on: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: ControlMetrics.previewRadius / 2, style: .continuous)
            .fill(on ? Palette.highlight : .clear)
            .padding(-Spacing.sm)
            .allowsHitTesting(false)
    }
}

private extension View {
    /// Выключенный модуль: видно, но приглушено и не нажимается.
    func inactive(_ inactive: Bool) -> some View {
        disabled(inactive)
            .opacity(inactive ? DisabledStyle.opacity : 1)
            .animation(Motion.base, value: inactive)
    }
}

/// Якорь строки формы. Нативная сгруппированная форма не прокручивается через `ScrollViewReader`,
/// поэтому к строке прокручивает AppKit: якорь знает своё место в прокрутке окна.
private struct RowAnchor: NSViewRepresentable {
    let id: String

    @MainActor private static var views: [String: WeakView] = [:]

    private final class WeakView {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        Self.views[id] = WeakView(view)
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) { Self.views[id] = WeakView(view) }

    /// Плавно ставит строку в середину видимой области.
    @MainActor static func scroll(to id: String) {
        guard let view = views[id]?.view, let scroll = view.enclosingScrollView else { return }
        let clip = scroll.contentView
        let frame = view.convert(view.bounds, to: clip.documentView ?? clip)
        let visible = clip.bounds.height
        let maxY = max((clip.documentView?.frame.height ?? 0) - visible, 0)
        // Координаты рамки и прокрутки в одной системе, переворачивать не нужно.
        let y = min(max(frame.midY - visible / 2, 0), maxY)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.25
            clip.animator().setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: y))
        }
        scroll.reflectScrolledClipView(clip)
    }
}
