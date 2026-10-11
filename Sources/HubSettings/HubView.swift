import AppKit
import SwiftUI

// Окно в духе настроек Raycast: сверху поиск по всем приложениям (⌘F) и вкладки приложений,
// ниже - экран приложения. У большого приложения (Island) слева список страниц с переключателями,
// справа - настройки выбранной. Технические настройки собраны в одну свёрнутую секцию «Для задротов».
// Всё применяется сразу; ⌘Z отменяет.
struct HubView: View {
    let model: HubModel
    let apps: AppMonitor
    @State private var query = ""
    /// Настройка или страница, которую надо показать и подсветить (выбрали в поиске или попросило приложение).
    @State private var target: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        let registry = ModuleRegistry(model: model, apps: apps)
        let modules = registry.modules
        let current = registry.module(model.selection)
        VStack(spacing: 0) {
            TopBar(query: $query, focused: $searchFocused, modules: modules, selected: current?.id) { id in
                query = ""
                withMotion(Motion.page) { model.selection = id }
            }
            Divider()
            ZStack {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    SearchResults(results: SearchIndex(modules: modules).search(query)) { module, hit in
                        query = ""
                        searchFocused = false
                        model.selection = module
                        target = hit
                    }
                    .transition(.opacity)
                } else if let current {
                    ModuleScreen(module: current, target: $target)
                        .id(current.id)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .motion(Motion.page, value: current?.id)
        }
        .background { ZStack { GlassBackground(); Glass.tint }.ignoresSafeArea() }
        .environment(\.colorScheme, .dark)
        .tint(Glass.controlTint)
        .background {
            // ⌘F - к строке поиска; Esc в ней - очистить.
            Button("") { searchFocused = true }
                .keyboardShortcut("f")
                .hidden()
        }
        .onChange(of: model.pendingTarget) { _, pending in
            guard let pending else { return }
            model.pendingTarget = nil
            query = ""
            target = pending
        }
    }
}

// MARK: - верх окна

/// Поиск по центру и вкладки приложений под ним. Пустое место тянет окно: заголовок окна скрыт.
private struct TopBar: View {
    @Binding var query: String
    var focused: FocusState<Bool>.Binding
    let modules: [any SettingsModule]
    let selected: String?
    let select: (String) -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            SearchField(query: $query, focused: focused)
                .frame(maxWidth: TopBarMetrics.searchWidth)
                .padding(.horizontal, TopBarMetrics.trafficLightsInset)
            HStack(spacing: Spacing.xs) {
                ForEach(modules, id: \.id) { module in
                    TabButton(module: module, selected: module.id == selected && query.isEmpty) { select(module.id) }
                }
            }
        }
        .padding(.top, TopBarMetrics.top)
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: .infinity)
    }
}

private struct SearchField: View {
    @Binding var query: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Поиск настроек", text: $query)
                .textFieldStyle(.plain)
                .focused(focused)
                .onExitCommand { query = "" }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить")
            } else {
                Text("⌘F")
                    .font(TextStyle.shortcut)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, Spacing.md + Spacing.xs)
        .frame(height: TopBarMetrics.searchHeight)
        .background(Glass.card, in: RoundedRectangle(cornerRadius: TopBarMetrics.searchRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TopBarMetrics.searchRadius, style: .continuous)
                .strokeBorder(focused.wrappedValue ? Color.white.opacity(0.28) : Palette.hairline, lineWidth: 1)
        }
        .animation(Motion.fast, value: focused.wrappedValue)
    }
}

/// Вкладка приложения: значок и название; выбранная - на подложке. Выключенное приложение - серым.
private struct TabButton: View {
    let module: any SettingsModule
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let off = module.power.map { !$0.isOn } ?? false
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                ModuleTile(symbol: module.symbol, tint: module.tint, size: TileMetrics.tab)
                    .saturation(off ? 0 : 1)
                Text(module.title)
                    .font(TextStyle.tab)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .padding(.horizontal, Spacing.md + Spacing.xxs)
            .frame(height: TopBarMetrics.tabHeight)
            .background {
                RoundedRectangle(cornerRadius: TopBarMetrics.tabRadius, style: .continuous)
                    .fill(selected ? Glass.selected : hovering ? Glass.hover : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.fast, value: hovering)
        .animation(Motion.fast, value: selected)
        .help(off ? "\(module.title) выключено" : module.summary)
    }
}

// MARK: - плитка

/// Белый символ в цветном скруглённом квадрате - значок модуля или страницы.
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
            .background(Glass.tile, in: shape)
            .overlay { shape.strokeBorder(Glass.tileStroke, lineWidth: 0.5) }
            .accessibilityHidden(true)
    }
}

// MARK: - экран приложения

/// Экран приложения. С подстраницами - список слева и выбранная справа; без них - одна страница.
private struct ModuleScreen: View {
    let module: any SettingsModule
    @Binding var target: String?
    /// Выбранная страница списка; `rootID` - главная страница приложения.
    @State private var page: String
    @State private var flashing: String?

    static let rootID = "root"

    init(module: any SettingsModule, target: Binding<String?>) {
        self.module = module
        _target = target
        let saved = UserDefaults.standard.string(forKey: "page.\(module.id)")
        let exists = saved.map { $0 == Self.rootID || module.page($0) != nil } ?? false
        _page = State(initialValue: exists ? saved! : Self.rootID)
    }

    var body: some View {
        Group {
            if module.pageGroups.isEmpty {
                detail
            } else {
                HStack(spacing: 0) {
                    PageList(module: module, selection: $page)
                        .frame(width: ScreenMetrics.listWidth)
                    Divider()
                    detail
                }
            }
        }
        .onAppear { reveal(target) }
        .onChange(of: target) { _, new in reveal(new) }
        .onChange(of: page) { _, new in UserDefaults.standard.set(new, forKey: "page.\(module.id)") }
    }

    @ViewBuilder
    private var detail: some View {
        ZStack {
            if page == Self.rootID || module.page(page) == nil {
                PageDetail(content: .root(module), flashing: flashing)
                    .id(Self.rootID)
            } else if let current = module.page(page) {
                PageDetail(content: .page(current, module: module), flashing: flashing)
                    .id(current.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .motion(Motion.fast, value: page)
    }

    /// Открывает страницу с нужной настройкой, прокручивает к строке и подсвечивает её.
    private func reveal(_ id: String?) {
        guard let id else { return }
        target = nil
        if let pageID = id.hasPrefix(SearchIndex.pagePrefix) ? String(id.dropFirst(SearchIndex.pagePrefix.count)) : nil {
            page = topPage(containing: pageID) ?? Self.rootID
            flash(pageID)
            return
        }
        let optionID = id.hasPrefix("\(module.id).") ? id : "\(module.id).\(id.drop { $0 == "#" })"
        guard let place = module.allOptions.first(where: { $0.option.id == optionID }) else { return }
        page = place.pages.first?.id ?? Self.rootID
        flash(optionID)
    }

    private func flash(_ id: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            RowAnchor.scroll(to: id)
            withMotion { flashing = id }
            try? await Task.sleep(for: Motion.highlightDuration)
            withMotion(Motion.highlightFade) { if flashing == id { flashing = nil } }
        }
    }

    /// Страница списка, внутри которой лежит страница `id` (сама она или её родитель).
    private func topPage(containing id: String) -> String? {
        func contains(_ page: SettingsPage) -> Bool {
            page.id == id || page.subgroups.contains { $0.pages.contains(where: contains) }
        }
        return module.pageGroups.flatMap(\.pages).first(where: contains)?.id
    }
}

// MARK: - список страниц

private struct PageList: View {
    let module: any SettingsModule
    @Binding var selection: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                PageListRow(title: "Общее", symbol: module.symbol, power: nil,
                            selected: selection == ModuleScreen.rootID) { selection = ModuleScreen.rootID }
                ForEach(module.pageGroups) { group in
                    if let title = group.title {
                        Text(title)
                            .font(TextStyle.sidebarStatus.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.top, Spacing.lg)
                            .padding(.bottom, Spacing.xs)
                    }
                    ForEach(group.pages) { page in
                        PageListRow(title: page.title, symbol: page.symbol, power: page.power,
                                    selected: selection == page.id) { selection = page.id }
                    }
                }
            }
            .padding(Spacing.md)
        }
        .scrollIndicators(.never)
    }
}

/// Строка списка: плитка, название и маленький переключатель страницы справа.
private struct PageListRow: View {
    let title: String
    let symbol: String
    let power: PagePower?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let off = power.map { !$0.isOn() } ?? false
        HStack(spacing: Spacing.tileLabel) {
            ModuleTile(symbol: symbol, tint: .clear, size: TileMetrics.sidebar)
                .opacity(off ? 0.45 : 1)
            Text(title)
                .lineLimit(1)
                .foregroundStyle(off ? .tertiary : selected ? .primary : .secondary)
            Spacer(minLength: Spacing.xs)
            if let power {
                power.option.row()
                    .switchOnly()
                    .controlSize(.mini)
                    .fixedSize()
            }
        }
        .padding(.horizontal, Spacing.sm)
        .frame(height: 30)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Glass.selected : hovering ? Glass.hover : .clear)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
        .animation(Motion.fast, value: hovering)
        .animation(Motion.fast, value: selected)
    }
}

// MARK: - страница

/// Что показывает правая часть: главная страница приложения или одна из его страниц.
private enum PageContent {
    case root(any SettingsModule)
    case page(SettingsPage, module: any SettingsModule)
}

/// Шапка страницы (плитка, название, описание, главный переключатель) и форма с настройками.
/// Вложенные страницы («Текст песни» у «Музыки») - карточками ниже, со своим переключателем.
/// Все технические секции страницы - в одной свёрнутой секции «Для задротов» в самом низу.
private struct PageDetail: View {
    let content: PageContent
    let flashing: String?
    @State private var nerdOpen = false

    var body: some View {
        let parts = self.parts
        let nerd = parts.advanced
        let inactive = parts.inactive
        Form {
            Section {
                Header(content: content)
            }
            ForEach(parts.main) { block in
                BlockView(block: block, flashing: flashing, inactive: inactive)
            }
            if !nerd.isEmpty {
                Section {
                    Button {
                        withMotion(Motion.spring) { nerdOpen.toggle() }
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "chevron.right")
                                .font(TextStyle.chevron)
                                .rotationEffect(.degrees(nerdOpen ? 90 : 0))
                            Text("Для задротов")
                            Spacer()
                            Text("\(nerd.reduce(0) { $0 + $1.section.options.count })")
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } footer: {
                    if !nerdOpen {
                        Footer(text: "Размеры, отступы, интервалы и прочие тонкости. Обычно трогать не нужно.")
                    }
                }
                if nerdOpen || nerd.contains(where: { $0.section.options.contains { $0.id == flashing } }) {
                    ForEach(nerd) { block in
                        BlockView(block: block, flashing: flashing, inactive: inactive)
                    }
                }
            }
            if case let .root(module) = content, let reset = module.reset {
                Section {
                    HStack {
                        Spacer()
                        Button("Сбросить настройки \(module.title)", role: .destructive) {
                            withMotion(Motion.spring) { reset() }
                        }
                        .disabled(!module.canReset)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: ScreenMetrics.formMaxWidth)
        .frame(maxWidth: .infinity)
    }

    /// Секции страницы и вложенных страниц, разложенные на видимые и «для задротов».
    private var parts: (main: [Block], advanced: [Block], inactive: Bool) {
        var main: [Block] = []
        var advanced: [Block] = []
        func add(_ sections: [SettingsSection], prefix: String?, inactive: Bool) {
            for section in sections {
                let block = Block(section: section, prefix: prefix, inactive: inactive)
                if section.collapsed { advanced.append(block) } else { main.append(block) }
            }
        }
        switch content {
        case let .root(module):
            add(module.sections, prefix: nil, inactive: false)
            return (main, advanced, module.power.map { !$0.isOn } ?? false)
        case let .page(page, _):
            let off = page.power.map { !$0.isOn() } ?? false
            add(page.sections, prefix: nil, inactive: false)
            for child in page.subgroups.flatMap(\.pages) {
                let childOff = child.power.map { !$0.isOn() } ?? false
                main.append(Block(child: child))
                add(child.sections, prefix: child.title, inactive: childOff)
            }
            return (main, advanced, off)
        }
    }
}

/// Одна секция формы: обычная секция настроек или заголовок вложенной страницы с её переключателем.
private struct Block: Identifiable {
    var section: SettingsSection
    var prefix: String?
    var inactive = false
    var child: SettingsPage?

    var id: String { child.map { "child.\($0.id)" } ?? section.id }

    init(section: SettingsSection, prefix: String?, inactive: Bool) {
        self.section = section
        self.prefix = prefix
        self.inactive = inactive
    }

    init(child: SettingsPage) {
        self.child = child
        section = SettingsSection(id: "child.\(child.id)", options: [])
    }

    var title: String? {
        switch (prefix, section.title) {
        case let (prefix?, title?): "\(prefix): \(title)"
        case let (prefix?, nil): section.collapsed ? prefix : nil
        case let (nil, title): title
        }
    }
}

private struct BlockView: View {
    let block: Block
    let flashing: String?
    let inactive: Bool

    var body: some View {
        if let child = block.child {
            Section {
                ChildHeader(page: child)
                    .id(child.id)
                    .background(RowAnchor(id: child.id))
                    .background { Highlight(on: flashing == child.id) }
            }
            .inactive(inactive)
        } else {
            Section {
                ForEach(block.section.options) { option in
                    option.row()
                        .id(option.id)
                        .background(RowAnchor(id: option.id))
                        .background { Highlight(on: flashing == option.id) }
                }
            } header: {
                if let title = block.title { Text(title) }
            } footer: {
                if let footer = block.section.footer { Footer(text: footer) }
            }
            .inactive(inactive || block.inactive)
        }
    }
}

/// Шапка экрана: крупная плитка, название, описание и главный переключатель справа.
private struct Header: View {
    let content: PageContent

    var body: some View {
        HStack(spacing: Spacing.headerTile) {
            switch content {
            case let .root(module):
                ModuleTile(symbol: module.symbol, tint: module.tint, size: TileMetrics.header)
                titles(module.title, module.summary)
                Spacer(minLength: Spacing.lg)
                if let power = module.power { ModuleSwitch(power: power) }
            case let .page(page, _):
                ModuleTile(symbol: page.symbol, tint: page.tint, size: TileMetrics.header)
                titles(page.title, page.subtitle)
                Spacer(minLength: Spacing.lg)
                if let power = page.power {
                    power.option.row()
                        .switchOnly()
                        .toggleStyle(GlassSwitch())
                        .controlSize(.regular)
                }
            }
        }
        .padding(.vertical, Spacing.headerVertical)
    }

    private func titles(_ title: String, _ summary: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title).font(TextStyle.headerTitle)
            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(TextStyle.headerSummary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// «Включено» приложения: запускает и закрывает его.
private struct ModuleSwitch: View {
    let power: ModulePower

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if power.isBusy { ProgressView().controlSize(.small) }
            Toggle("Включено", isOn: Binding(get: { power.isOn }, set: { power.set($0) }))
                .switchOnly()
                .toggleStyle(GlassSwitch())
                .disabled(!power.available || power.isBusy)
        }
        .help(power.note ?? (power.isOn ? "Работает" : "Выключено"))
    }
}

/// Заголовок вложенной страницы: плитка, название, описание и её переключатель.
private struct ChildHeader: View {
    let page: SettingsPage

    var body: some View {
        HStack(spacing: Spacing.tileLabel + Spacing.xs) {
            ModuleTile(symbol: page.symbol, tint: page.tint, size: TileMetrics.row)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(page.title).font(TextStyle.childTitle)
                if let subtitle = page.subtitle {
                    Text(subtitle).font(TextStyle.searchResultPath).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Spacing.lg)
            if let power = page.power {
                power.option.row()
                    .switchOnly()
                    .toggleStyle(GlassSwitch())
                    .controlSize(ControlMetrics.switchSize)
            }
        }
    }
}

// MARK: - поиск

private struct SearchResults: View {
    let results: [SearchIndex.Result]
    let open: (String, String?) -> Void

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView.search
        } else {
            List {
                ForEach(results, id: \.module.id) { result in
                    Section(result.module.title) {
                        ForEach(result.hits) { hit in
                            Button { open(result.module.id, hit.target) } label: {
                                SearchRow(module: result.module, hit: hit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: ScreenMetrics.formMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct SearchRow: View {
    let module: any SettingsModule
    let hit: SearchIndex.Hit
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Spacing.tileLabel) {
            ModuleTile(symbol: module.symbol, tint: module.tint, size: TileMetrics.row)
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
            Spacer()
            Image(systemName: "arrow.turn.down.left")
                .foregroundStyle(.tertiary)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.sm)
        .background(hovering ? Glass.hover : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }
}

/// Поиск по названиям модулей, страниц и всех опций (подпись, пояснение, варианты выбора, название секции).
@MainActor
struct SearchIndex {
    let modules: [any SettingsModule]

    static let pagePrefix = "page:"

    struct Hit: Identifiable {
        let moduleID: String
        /// Куда перейти: id опции или «page:<id>» для страницы; nil - сам модуль.
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
                            hits.append(Hit(moduleID: module.id, target: Self.pagePrefix + page.id, title: page.title,
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
            if !hits.isEmpty {
                // Одна и та же строка может найтись дважды (переключатель страницы и её опция).
                var seen = Set<String>()
                let unique = hits.sorted { $0.rank < $1.rank }.filter { seen.insert($0.id).inserted }
                results.append(Result(module: module, hits: unique))
            }
        }
        return results
    }
}

// MARK: - мелочи

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
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(on ? Color.white.opacity(0.12) : .clear)
            .padding(-Spacing.sm)
            .allowsHitTesting(false)
    }
}

private extension View {
    /// Выключенное: видно, но приглушено и не нажимается.
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
        let y = min(max(frame.midY - visible / 2, 0), maxY)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.25
            clip.animator().setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: y))
        }
        scroll.reflectScrolledClipView(clip)
    }
}
