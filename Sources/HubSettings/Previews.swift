import AppKit
import IslandUI
import SidebarUI
import SuiteKit
import SwiftUI

// Живые превью над настройками. Это не рисунки: внутри настоящие интерфейсы острова и панели (библиотеки
// IslandUI и SidebarUI) с настоящими данными, поэтому превью неотличимо от приложения.
// Поверх - ручки, как в графическом редакторе: тянешь край - меняется размер, и в превью, и в приложении.
// Вкладки и виджеты можно перетаскивать (порядок) и вытаскивать наружу (убрать); убранные лежат в лотке под превью.

struct AppPreview: View {
    let model: HubModel
    let schema: SuiteSchema

    var body: some View {
        switch schema.preview {
        case "island": IslandPreviewStage(model: model, schema: schema)
        case "sidebar": SidebarPreviewStage(model: model, schema: schema)
        default: EmptyView()
        }
    }

    static func exists(for schema: SuiteSchema) -> Bool {
        ["island", "sidebar"].contains(schema.preview ?? "")
    }
}

// MARK: - общее

/// Первое поле-список схемы: его значки живут в превью.
@MainActor
private struct ListBinding {
    let model: HubModel
    let app: String
    let field: SuiteSchema.Field

    init?(model: HubModel, schema: SuiteSchema) {
        guard let field = schema.groups.flatMap(\.fields).first(where: { $0.kind == .list }) else { return nil }
        self.model = model
        app = schema.app
        self.field = field
    }

    var options: [SuiteSchema.Field.Option] { field.options ?? [] }

    var enabled: [String] {
        (model.value(app, field.key)?.strings ?? []).filter { id in options.contains { $0.value == id } }
    }

    var available: [SuiteSchema.Field.Option] { options.filter { !enabled.contains($0.value) } }

    func option(_ id: String) -> SuiteSchema.Field.Option? { options.first { $0.value == id } }

    func save(_ list: [String]) {
        model.set(app, field.key, .array(list.map { .string($0) }))
    }
}

/// Сцена превью на весь холст: «обои» macOS, внизу лоток с убранными значками.
private struct Stage<Content: View, Corner: View>: View {
    let list: ListBinding?
    let hint: String
    @ViewBuilder var content: () -> Content
    /// Переключатель состояния в левом нижнем углу сцены.
    @ViewBuilder var corner: () -> Corner

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Wallpaper()
                content()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                corner()
                    .padding(Spacing.lg)
                    .environment(\.colorScheme, .dark)
            }
            if let list {
                Tray(list: list, hint: hint)
            }
        }
        .background(Color.clear)
    }
}

/// Обои в духе macOS: мягкие цветные пятна системных оттенков.
/// Пятна - радиальные градиенты, а не размытые круги: размытие радиусом 90 пересчитывалось на каждом кадре
/// прокрутки формы, и окно заметно тормозило. Градиент рисуется один раз.
private struct Wallpaper: View {
    var body: some View {
        // Пятна - поверх фона, а не рядом с ним в стопке: их размер не должен распирать сцену.
        LinearGradient(colors: [PreviewStyle.wallpaperTop, PreviewStyle.wallpaperBottom],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                ZStack {
                    glow(PreviewStyle.glowA, radius: 280).offset(x: -190, y: 90)
                    glow(PreviewStyle.glowB, radius: 240).offset(x: 220, y: 130)
                    glow(PreviewStyle.glowC, radius: 200).offset(x: 60, y: -110)
                }
            }
            .clipped()
            .drawingGroup()
    }

    private func glow(_ color: Color, radius: CGFloat) -> some View {
        RadialGradient(colors: [color, color.opacity(0)], center: .center, startRadius: 0, endRadius: radius)
            .frame(width: radius * 2, height: radius * 2)
    }
}

/// Лоток под превью: убранные значки, по нажатию возвращаются в конец.
private struct Tray: View {
    let list: ListBinding
    let hint: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            if list.available.isEmpty {
                Image(systemName: "hand.draw")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .transition(.opacity)
            } else {
                Text("Добавить")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                // Вариантов бывает много: лоток прокручивается вбок, подписи не сжимаются.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(list.available, id: \.value) { option in
                            TrayChip(option: option) {
                                withMotion(Motion.spring) { list.save(list.enabled + [option.value]) }
                            }
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                        }
                    }
                    .padding(.trailing, Spacing.xl)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xl)
        .frame(height: PreviewStyle.trayHeight)
        .overlay(alignment: .top) { Divider() }
        .animation(Motion.spring, value: list.available.map(\.value))
    }
}

private struct TrayChip: View {
    let option: SuiteSchema.Field.Option
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: option.symbol ?? "circle")
                    .font(.system(size: 11, weight: .semibold))
                Text(option.title)
                    .font(.callout)
                    .fixedSize()
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hover ? Palette.accent : Color.secondary)
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, Spacing.md)
            .frame(height: PreviewStyle.trayChipHeight)
            .background(hover ? Palette.keyCapBackground : Palette.keyCapBackground.opacity(0.6), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Motion.fast, value: hover)
        .help("Вернуть «\(option.title)»")
    }
}

/// Строка меню с чёлкой посередине.
private struct MenuBar: View {
    let height: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "apple.logo").font(.system(size: 13, weight: .medium))
            ForEach([40, 26, 30, 36], id: \.self) { width in
                Capsule().frame(width: CGFloat(width), height: 6).opacity(0.75)
            }
            Spacer()
            Image(systemName: "wifi").font(.system(size: 12, weight: .semibold))
            Image(systemName: "battery.75percent").font(.system(size: 14))
            Capsule().frame(width: 52, height: 6).opacity(0.75)
        }
        .foregroundStyle(PreviewStyle.menuBarText)
        .padding(.horizontal, 16)
        .frame(height: height)
        .background(PreviewStyle.menuBarTint)
    }
}

// MARK: - ручки

/// Ручка на краю: белая пилюля с акцентной обводкой. Тянется вдоль одной оси; значение читается в начале жеста,
/// поэтому ничего не накапливается и не уплывает.
private struct EdgeHandle: View {
    let axis: Axis
    let cursor: NSCursor
    /// Сдвиг курсора от начала жеста, в точках превью.
    let onDrag: (_ start: Double, _ delta: CGFloat) -> Void
    let value: () -> Double
    @Binding var active: Bool
    var onBegin: () -> Void = {}
    @State private var start: Double?
    @State private var hover = false

    var body: some View {
        Capsule()
            .fill(PreviewStyle.handleFill)
            .overlay { Capsule().strokeBorder(Palette.accent, lineWidth: PreviewStyle.handleStroke) }
            .frame(width: axis == .horizontal ? PreviewStyle.edgeHandleShort : PreviewStyle.edgeHandleLong,
                   height: axis == .horizontal ? PreviewStyle.edgeHandleLong : PreviewStyle.edgeHandleShort)
            .scaleEffect(hover || start != nil ? 1.2 : 1)
            .shadow(color: PreviewStyle.handleShadow, radius: 3, y: 1)
            // Попасть легко: зона захвата больше самой пилюли.
            .padding(PreviewStyle.handleHitPadding)
            .contentShape(Rectangle())
            .onHover { inside in
                hover = inside
                if inside { cursor.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { drag in
                        if start == nil { start = value(); active = true; onBegin() }
                        onDrag(start ?? 0, axis == .horizontal ? drag.translation.width : drag.translation.height)
                    }
                    .onEnded { _ in start = nil; active = false }
            )
            .animation(Motion.fast, value: hover)
    }
}

/// Размер под фигурой, пока её тянут: «440 × 222».
private struct SizeBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(height: PreviewStyle.badgeHeight)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: PreviewStyle.badgeRadius, style: .continuous))
            .contentTransition(.numericText())
    }
}

// MARK: - остров

private struct IslandPreviewStage: View {
    let model: HubModel
    let schema: SuiteSchema
    @State private var open = true
    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        let app = schema.app
        let list = ListBinding(model: model, schema: schema)
        let notch = IslandPreview.notch
        let side = max(model.number(app, "sideWidth"), 40)
        let extra = max(model.number(app, "extraHeight"), 0)
        // Раскрытый остров подстраивается под вкладку (до 580 pt), поэтому ручки есть только у свёрнутого.
        let widest = IslandPreview.largestOpenWidth
        let size = CGSize(width: notch.width + side * 2, height: notch.height + extra)
        let corner = model.number(app, "peekCorner")

        Stage(list: list,
              hint: open ? "Вкладки перетаскиваются, вниз - убрать. Размер подстраивается под вкладку сам."
                         : "Тяни за края острова. Нажми на ухо, чтобы выбрать, что в нём показывать.") {
            GeometryReader { proxy in
                // Превью в натуральную величину; уменьшается, только если раскрытый остров шире сцены.
                let scale = min(1, (proxy.size.width - 48) / (widest + 28))
                ZStack(alignment: .top) {
                    MenuBar(height: notch.height)
                    IslandPreview(settings: model.settingsData(app), open: open, onTabsChange: { tabs in
                        list?.save(tabs)
                    }, onEdit: { key, value in
                        withMotion(Motion.spring) { model.set(app, key, value) }
                    })
                    if (hovering || dragging), !open {
                        handles(size: size, corner: corner, scale: scale)
                            .transition(.opacity)
                    }
                }
                .frame(width: proxy.size.width / scale, height: proxy.size.height / scale, alignment: .top)
                .scaleEffect(scale, anchor: .top)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        } corner: {
            Picker("Состояние острова", selection: Binding(get: { open }, set: { value in withMotion(Motion.spring) { open = value } })) {
                Text("Свёрнут").tag(false)
                Text("Раскрыт").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .onHover { inside in withMotion(Motion.base) { hovering = inside } }
        // Двигаешь размеры свёрнутого острова - превью сворачивается.
        .onChange(of: [side, extra, corner]) { if !dragging { open = false } }
    }

    /// Рамка выделения вокруг острова и ручки на ней: бока - ширина (симметрично), низ - высота, угол - скругление.
    @ViewBuilder
    private func handles(size: CGSize, corner: Double, scale: CGFloat) -> some View {
        let app = schema.app
        ZStack {
            Rectangle()
                .strokeBorder(Palette.accent, lineWidth: 1)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
            ForEach([-1.0, 1.0], id: \.self) { direction in
                EdgeHandle(axis: .horizontal, cursor: .resizeLeftRight, onDrag: { start, delta in
                    // Сдвиг края на 1 pt - это 1 pt с каждой стороны от чёлки.
                    model.setNumber(app, "sideWidth", start + Double(delta / scale) * direction)
                }, value: { model.number(app, "sideWidth") }, active: $dragging,
                           onBegin: { model.focusKey = "sideWidth" })
                    .offset(x: direction * size.width / 2)
            }
            EdgeHandle(axis: .vertical, cursor: .resizeUpDown, onDrag: { start, delta in
                model.setNumber(app, "extraHeight", start + Double(delta / scale))
            }, value: { model.number(app, "extraHeight") }, active: $dragging,
                       onBegin: { model.focusKey = "extraHeight" })
                .offset(y: size.height / 2)
            SizeBadge(text: "\(Int(size.width)) × \(Int(size.height))")
                .offset(y: size.height / 2 + 24)
        }
        .frame(width: size.width, height: size.height)
        .animation(dragging ? nil : Motion.spring, value: size)
    }
}

// MARK: - боковая панель

private struct SidebarPreviewStage: View {
    let model: HubModel
    let schema: SuiteSchema
    @State private var hovering = false
    @State private var dragging = false
    @State private var panel = CGSize(width: 46, height: 200)

    private let menuBar = PreviewStyle.menuBarHeight
    /// Высота холста: от неё считается, где стоит панель.
    @State private var height: CGFloat = 460

    var body: some View {
        let app = schema.app
        let list = ListBinding(model: model, schema: schema)
        let mode = model.value(app, "mode")?.string ?? "always"
        let hidden = mode != "always" && !hovering && !dragging
        let area = height - menuBar
        let position = min(max(model.number(app, "position"), -1), 1)
        let centerY = menuBar + area / 2 + position * max(area - panel.height, 0) / 2

        Stage(list: list,
              hint: "Тяни за левый край и за ручку со стрелками. Виджеты перетаскиваются, влево - убрать.") {
            ZStack(alignment: .topLeading) {
                MenuBar(height: menuBar)
                if hidden {
                    Label(mode == "edge" ? "Наведи курсор, и рейка выедет из-за края" : "Рейка спрятана, появляется по клавише",
                          systemImage: mode == "edge" ? "cursorarrow.rays" : "keyboard")
                        .font(.callout)
                        .foregroundStyle(PreviewStyle.hintText)
                        .padding(.horizontal, Spacing.lg)
                        .frame(height: PreviewStyle.trayChipHeight)
                        .background(PreviewStyle.hintBackground, in: Capsule())
                        .padding(.leading, Spacing.xl)
                        .padding(.top, menuBar + Spacing.xl)
                        .transition(.opacity)
                }
                SidebarPreview(settings: model.settingsData(app), hidden: hidden,
                               onWidgetsChange: { list?.save($0) }, onPanelSize: { panel = $0 })
                    .padding(.top, menuBar)
                if (hovering || dragging), !hidden {
                    handles(centerY: centerY, area: area)
                        .transition(.opacity)
                }
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        } corner: {
            EmptyView()
        }
        .onHover { inside in withMotion(Motion.spring) { hovering = inside } }
        .animation(Motion.spring, value: hidden)
    }

    /// Рамка вокруг панели, ручка ширины на левом краю и ручка перемещения по высоте.
    @ViewBuilder
    private func handles(centerY: CGFloat, area: CGFloat) -> some View {
        let app = schema.app
        let key = "railWidth"
        GeometryReader { proxy in
            let left = proxy.size.width - panel.width
            Rectangle()
                .strokeBorder(Palette.accent, lineWidth: 1)
                .frame(width: panel.width, height: panel.height)
                .position(x: left + panel.width / 2, y: centerY)
                .allowsHitTesting(false)
            EdgeHandle(axis: .horizontal, cursor: .resizeLeftRight, onDrag: { start, delta in
                model.setNumber(app, key, start - Double(delta))
            }, value: { model.number(app, key) }, active: $dragging, onBegin: { model.focusKey = key })
                .position(x: left, y: centerY)
            MoveHandle(active: $dragging, value: { model.number(app, "position") }) { start, delta in
                let travel = max(area - panel.height, 1) / 2
                model.setNumber(app, "position", start + Double(delta / travel))
            }
            .position(x: left - 22, y: centerY - panel.height / 2 + 14)
            SizeBadge(text: "\(Int(panel.width)) × \(Int(panel.height))")
                .position(x: left - 44, y: centerY + panel.height / 2 - 10)
        }
    }
}

/// Ручка перемещения: кружок со стрелками, тянется по вертикали.
private struct MoveHandle: View {
    @Binding var active: Bool
    let value: () -> Double
    let onDrag: (_ start: Double, _ delta: CGFloat) -> Void
    @State private var start: Double?
    @State private var hover = false

    var body: some View {
        Image(systemName: "arrow.up.and.down")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Palette.accent)
            .frame(width: PreviewStyle.moveHandle, height: PreviewStyle.moveHandle)
            .background(PreviewStyle.handleFill, in: Circle())
            .overlay { Circle().strokeBorder(Palette.accent, lineWidth: PreviewStyle.handleStroke) }
            .scaleEffect(hover || start != nil ? 1.15 : 1)
            .shadow(color: PreviewStyle.handleShadow, radius: 3, y: 1)
            .padding(6)
            .contentShape(Rectangle())
            .onHover { inside in
                hover = inside
                if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { drag in
                        if start == nil { start = value(); active = true }
                        onDrag(start ?? 0, drag.translation.height)
                    }
                    .onEnded { _ in start = nil; active = false }
            )
            .help("Положение панели по высоте")
            .animation(Motion.fast, value: hover)
    }
}
