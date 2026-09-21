import AppKit
import SuiteKit
import SwiftUI

// Раскладка как в графическом редакторе: слева приложения, в центре холст с живым превью (оно не уезжает
// при прокрутке), справа инспектор с настройками. Всё применяется сразу, без «Сохранить»; ⌘Z отменяет.
struct HubView: View {
    let model: HubModel

    var body: some View {
        HStack(spacing: 0) {
            AppRail(model: model)
                .frame(width: 180)
            NL.border.frame(width: 1)
            if let schema = model.selected {
                Group {
                    if AppPreview.exists(for: schema) {
                        AppPreview(model: model, schema: schema)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        NL.border.frame(width: 1)
                        Inspector(model: model, schema: schema)
                            .frame(width: 340)
                    } else {
                        Inspector(model: model, schema: schema)
                            .frame(maxWidth: 560)
                            .frame(maxWidth: .infinity)
                    }
                }
                .id(schema.app)
                .transition(.opacity.animation(.easeOut(duration: 0.15)))
            } else {
                EmptyHub()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(NL.surface)
        .ignoresSafeArea()
        .motion(Motion.moderate, value: model.selected?.app)
    }
}

/// Колонка приложений, как в Системных настройках: системный материал, у каждого приложения цветная плитка
/// со значком, выбранное залито акцентом.
private struct AppRail: View {
    let model: HubModel
    @Namespace private var namespace

    private static let tints = [Color.black, NL.indigo, NL.warning, NL.success, NL.pink, NL.teal]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s0_5) {
            ForEach(Array(model.schemas.enumerated()), id: \.element.app) { index, schema in
                RailItem(schema: schema, tint: Self.tints[index % Self.tints.count],
                         selected: model.selected?.app == schema.app, namespace: namespace) {
                    withMotion(Motion.spring) { model.selection = schema.app }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s2 + 2)
        // Под кнопками окна: заголовка у окна нет, колонка начинается сразу под ними.
        .padding(.top, 52)
        .padding(.bottom, Space.s3)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(VisualEffect(material: .sidebar))
    }

    private struct RailItem: View {
        let schema: SuiteSchema
        let tint: Color
        let selected: Bool
        let namespace: Namespace.ID
        let action: () -> Void
        @State private var hover = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: Space.s2) {
                    Image(systemName: schema.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        }
                    Text(schema.title)
                        .nlType(.bodySm)
                        .foregroundStyle(selected ? NL.textOnAccent : NL.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.s2)
                .frame(height: 34)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(NL.selected)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    } else if hover {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(NL.hover)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .animation(Motion.fast, value: hover)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

/// Системный материал под содержимым (полупрозрачная колонка, как у Finder и Системных настроек).
struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context _: Context) { view.material = material }
}

/// Инспектор: шапка с названием и «Сбросить», поиск по настройкам и сворачиваемые секции.
private struct Inspector: View {
    let model: HubModel
    let schema: SuiteSchema
    @State private var query = ""
    @State private var collapsed: Set<String> = []
    @State private var flash: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            NL.border.frame(height: 1)
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        ForEach(Array(groups.enumerated()), id: \.element.title) { index, group in
                            section(group)
                                .modifier(Appear(index: index))
                        }
                        if groups.isEmpty {
                            Text("Ничего не нашлось по запросу «\(query)»")
                                .nlType(.bodySm)
                                .foregroundStyle(NL.textSecondary)
                                .padding(Space.insetMd)
                        }
                    }
                    .padding(.bottom, Space.s6)
                }
                // Потянул ручку в превью - инспектор показывает поле, которое она меняет.
                .onChange(of: model.focusKey) { _, key in
                    guard let key, let group = schema.groups.first(where: { $0.fields.contains { $0.key == key } }) else { return }
                    model.focusKey = nil
                    query = ""
                    withMotion(Motion.spring) {
                        collapsed.remove(group.title)
                        scroll.scrollTo(key, anchor: .center)
                        flash = key
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        withMotion(Motion.slow) { if flash == key { flash = nil } }
                    }
                }
            }
        }
        .background(NL.surface)
        .onAppear { collapsed = Set(UserDefaults.standard.stringArray(forKey: "collapsed.\(schema.app)") ?? []) }
        .onChange(of: collapsed) { UserDefaults.standard.set(Array(collapsed), forKey: "collapsed.\(schema.app)") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(schema.title)
                    .nlType(.heading)
                    .foregroundStyle(NL.textPrimary)
                Spacer(minLength: 0)
                Button { withMotion(Motion.spring) { model.undo() } } label: {
                    Label("Отменить", systemImage: "arrow.uturn.backward")
                }
                .nlIconButton(.md)
                .disabled(model.undoCount == 0)
                .help("Отменить (⌘Z)")
                Button("Сбросить всё") { withMotion(Motion.spring) { model.reset(schema) } }
                    .nlButton(.secondary, .sm)
                    .disabled(model.isDefault(schema))
                    .help("Вернуть все настройки \(schema.title) к стандартным. Отменяется через ⌘Z.")
            }
            HStack(spacing: Space.s1_5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NL.iconTertiary)
                TextField("Найти настройку", text: $query)
                    .textFieldStyle(.plain)
                    .nlType(.bodySm)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(NL.iconTertiary)
                }
            }
            .padding(.horizontal, Space.s2)
            .frame(height: Size.controlSm)
            .background(NL.subtle, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .padding(.horizontal, Space.insetMd)
        .padding(.top, 44)
        .padding(.bottom, Space.s3)
    }

    /// Секции с видимыми полями; при поиске остаются только подходящие поля.
    private var groups: [SuiteSchema.Group] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        return schema.groups.compactMap { group in
            var copy = group
            copy.fields = group.fields.filter { field in
                guard model.isVisible(field, in: schema.app) else { return false }
                guard !text.isEmpty else { return true }
                let haystack = ([field.title, field.help ?? "", group.title] + (field.options ?? []).map(\.title)).joined(separator: " ")
                return haystack.lowercased().contains(text)
            }
            return copy.fields.isEmpty ? nil : copy
        }
    }

    @ViewBuilder
    private func section(_ group: SuiteSchema.Group) -> some View {
        let isCollapsed = collapsed.contains(group.title) && query.isEmpty
        let changed = group.fields.filter { !model.isDefault(schema.app, $0) }.count
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withMotion(Motion.spring) {
                    if isCollapsed { collapsed.remove(group.title) } else { collapsed.insert(group.title) }
                }
            } label: {
                HStack(spacing: Space.s1_5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(NL.iconTertiary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    Text(group.title)
                        .nlType(.headingXs)
                        .foregroundStyle(NL.textPrimary)
                    if changed > 0 {
                        Text("\(changed)")
                            .nlType(.labelXs)
                            .foregroundStyle(NL.accent)
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(NL.accentSubtle, in: Capsule())
                            .help("Изменено настроек: \(changed)")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.insetMd)
                .frame(height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !isCollapsed {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.fields, id: \.key) { field in
                        FieldView(model: model, app: schema.app, field: field, flash: flash == field.key)
                            .id(field.key)
                            .transition(.opacity)
                    }
                    if let footer = group.footer, query.isEmpty {
                        FormFooter(footer)
                            .padding(.horizontal, Space.insetMd)
                            .padding(.top, Space.s1)
                    }
                }
                .padding(.bottom, Space.s3)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .overlay(alignment: .bottom) { NL.borderSubtle.frame(height: 1) }
        .clipped()
    }
}

/// Карточки страницы появляются по очереди: снизу вверх на 10pt, каждая чуть позже предыдущей.
private struct Appear: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                withAnimation(.easeOut(duration: 0.35).delay(Double(index) * 0.045)) { shown = true }
            }
    }
}

/// Ни одно приложение набора ещё не запускалось: схем нет.
private struct EmptyHub: View {
    var body: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(NL.iconTertiary)
                .frame(width: Size.iconXl, height: Size.iconXl)
            Text("Пока нечего настраивать")
                .nlType(.headingXs)
                .foregroundStyle(NL.textPrimary)
            Text("Запустите Island или Sidebar, и их настройки появятся здесь.")
                .nlType(.bodySm)
                .foregroundStyle(NL.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
    }
}
