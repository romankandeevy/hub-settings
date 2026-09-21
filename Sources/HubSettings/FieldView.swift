import AppKit
import Carbon.HIToolbox
import SuiteKit
import SwiftUI

/// Одно поле схемы: строка с названием слева и контролом справа.
/// Список (`list`) занимает несколько строк: по строке на вариант.
struct FieldView: View {
    let model: HubModel
    let app: String
    let field: SuiteSchema.Field
    var flash = false

    var body: some View {
        switch field.kind {
        case .toggle:
            row { toggle }
        case .number:
            row(scrub: true) { NumberControl(field: field, value: binding(number: 0)) }
        case .choice:
            row(stacked: (field.options ?? []).count <= 3) { choice }
        case .hotkey:
            row {
                HotKeyRecorder(
                    keyCode: Int(model.value(app, field.key)?.number ?? 0),
                    modifiers: model.value(app, field.modifiersKey ?? "")?.strings ?? []
                ) { code, modifiers in
                    model.set(app, field.key, .number(Double(code)))
                    if let key = field.modifiersKey { model.set(app, key, .array(modifiers.map { .string($0) })) }
                }
            }
        case .color:
            row(stacked: true) {
                ColorControl(options: field.options ?? [], value: Binding(
                    get: { model.value(app, field.key)?.string ?? "" },
                    set: { hex in withMotion(Motion.base) { model.set(app, field.key, .string(hex)) } }
                ))
            }
        case .list:
            OrderedList(model: model, app: app, field: field, last: true)
                .padding(.horizontal, Space.insetMd)
        }
    }

    private func row<Control: View>(scrub: Bool = false, stacked: Bool = false,
                                    @ViewBuilder _ control: @escaping () -> Control) -> some View {
        InspectorRow(model: model, app: app, field: field, flash: flash, scrub: scrub ? binding(number: 0) : nil,
                     stacked: stacked, control: control)
    }

    private var toggle: some View {
        // Подпись несёт сама строка; у переключателя она только для VoiceOver.
        Toggle("", isOn: Binding(
            get: { model.value(app, field.key)?.bool ?? false },
            set: { on in withMotion(Motion.base) { model.set(app, field.key, .bool(on)) } }
        ))
        .toggleStyle(NLSwitchStyle())
        .accessibilityLabel(field.title)
    }

    @ViewBuilder
    private var choice: some View {
        let options = (field.options ?? []).map { (value: $0.value, title: $0.title) }
        let selection = Binding(
            get: { model.value(app, field.key)?.string ?? "" },
            set: { value in withMotion { model.set(app, field.key, .string(value)) } }
        )
        if options.count <= 3 {
            Segmented(selection: selection, options: options)
        } else {
            NLSelect(selection: selection, options: options)
        }
    }

    private func binding(number fallback: Double) -> Binding<Double> {
        Binding(
            get: { model.value(app, field.key)?.number ?? fallback },
            set: { model.set(app, field.key, .number($0)) }
        )
    }
}

// MARK: - число

/// Ползунок и поле, в которое можно вписать точное число. Файл пишется на каждом шаге,
/// так что приложение меняется прямо во время перетаскивания.
private struct NumberControl: View {
    let field: SuiteSchema.Field
    @Binding var value: Double
    @State private var text = ""
    @FocusState private var editing: Bool

    var body: some View {
        let low = field.min ?? 0
        let high = max(field.max ?? 1, low)
        let step = field.step ?? 1
        HStack(spacing: Space.s2) {
            Slider(value: Binding(get: { min(max(value, low), high) }, set: { value = round($0 / step) * step }),
                   in: low...high)
                .controlSize(.mini)
                .tint(NL.accent)
                .frame(width: 96)
            HStack(spacing: 2) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .focused($editing)
                    .onSubmit { commit(low, high, step) }
                if let unit = field.unit {
                    Text(unit).foregroundStyle(NL.textTertiary)
                }
            }
            .nlType(.labelSm)
            .monospacedDigit()
            .foregroundStyle(NL.textPrimary)
            .padding(.horizontal, Space.s1_5)
            .frame(width: 62, height: 24)
            .background(NL.subtle, in: RoundedRectangle(cornerRadius: Radius.xs + 1, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.xs + 1, style: .continuous)
                    .strokeBorder(editing ? NL.borderFocus : .clear, lineWidth: 1)
            }
        }
        .onAppear { text = Self.format(value, step: step) }
        .onChange(of: value) { if !editing { text = Self.format(value, step: step) } }
        .onChange(of: editing) { _, now in if !now { commit(low, high, step) } }
    }

    private func commit(_ low: Double, _ high: Double, _ step: Double) {
        if let typed = Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) {
            value = min(max((typed / step).rounded() * step, low), high)
        }
        text = Self.format(value, step: step)
    }

    static func format(_ value: Double, step: Double) -> String {
        let digits = step >= 1 ? 0 : step >= 0.1 ? 1 : 2
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        formatter.usesGroupingSeparator = false
        return formatter.string(from: value as NSNumber) ?? "\(value)"
    }
}

/// Строка инспектора: название слева, контрол справа. У изменённой настройки слева синяя точка - нажми, чтобы
/// вернуть стандартное значение. За название числа можно тянуть влево-вправо, как в Figma. Пояснение - в подсказке.
private struct InspectorRow<Control: View>: View {
    let model: HubModel
    let app: String
    let field: SuiteSchema.Field
    let flash: Bool
    let scrub: Binding<Double>?
    /// Широкий контрол (сегменты, образцы цвета) встаёт под названием, а не справа от него.
    var stacked = false
    @ViewBuilder let control: () -> Control
    @State private var scrubStart: Double?
    @State private var hover = false

    var body: some View {
        let changed = !model.isDefault(app, field)
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s1_5))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Space.s2))
        layout {
            Text(field.title)
                .nlType(.bodySm)
                .foregroundStyle(NL.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(scrubGesture)
                .onHover { inside in
                    guard scrub != nil else { return }
                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
            control()
        }
        .padding(.horizontal, Space.insetMd)
        .padding(.vertical, stacked ? Space.s2 : 0)
        .frame(minHeight: 36)
        .background(flash ? NL.accentSubtle : hover ? NL.hover.opacity(0.5) : .clear)
        .overlay(alignment: .leading) {
            if changed {
                Button { withMotion(Motion.spring) { model.reset(app, field) } } label: {
                    Circle().fill(NL.accent).frame(width: 6, height: 6)
                        .frame(width: Space.insetMd, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Изменено. Нажми, чтобы вернуть стандартное значение.")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onHover { hover = $0 }
        .help(field.help ?? "")
        .contextMenu {
            Button("Вернуть стандартное значение") { withMotion(Motion.spring) { model.reset(app, field) } }
                .disabled(!changed)
        }
        .animation(Motion.base, value: changed)
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { drag in
                guard let scrub else { return }
                if scrubStart == nil { scrubStart = scrub.wrappedValue }
                let step = field.step ?? 1
                // 3 pt движения - один шаг; с Shift - в десять раз точнее не нужно, шаг и так мелкий.
                let value = (scrubStart ?? 0) + (drag.translation.width / 3).rounded() * step
                scrub.wrappedValue = min(max(value, field.min ?? -.infinity), field.max ?? .infinity)
            }
            .onEnded { _ in scrubStart = nil }
    }
}

// MARK: - цвет

/// Готовые образцы (системные цвета Apple) и свой цвет из системной палитры. Значение - строка «#RRGGBB».
private struct ColorControl: View {
    let options: [SuiteSchema.Field.Option]
    @Binding var value: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value.caseInsensitiveCompare(value) == .orderedSame
                Button { value = option.value } label: {
                    Circle()
                        .fill(Self.color(option.value))
                        .frame(width: 18, height: 18)
                        .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1) }
                        .padding(3)
                        .overlay { Circle().strokeBorder(selected ? NL.textPrimary : .clear, lineWidth: 2) }
                        .scaleEffect(selected ? 1 : 0.92)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(option.title)
            }
            ColorPicker("Свой цвет", selection: Binding(
                get: { Self.color(value) },
                set: { value = Self.hex($0) }
            ), supportsOpacity: false)
                .labelsHidden()
                .help("Свой цвет")
        }
    }

    static func color(_ hex: String) -> Color {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return .gray }
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }

    static func hex(_ color: Color) -> String {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .orange
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}

// MARK: - упорядоченный список

/// Включённые варианты сверху: строки можно перетаскивать за любое место. Выключенные ниже, в порядке схемы.
private struct OrderedList: View {
    let model: HubModel
    let app: String
    let field: SuiteSchema.Field
    let last: Bool

    var body: some View {
        let options = field.options ?? []
        let enabled = (model.value(app, field.key)?.strings ?? []).filter { id in options.contains { $0.value == id } }
        let disabled = options.filter { !enabled.contains($0.value) }
        VStack(spacing: 0) {
            ReorderStrip(axis: .vertical, items: enabled, length: Size.rowHeight, spacing: 0,
                         removeDistance: nil, onChange: save) { id, state in
                if let option = options.first(where: { $0.value == id }) {
                    row(option, on: true, state: state, last: last && disabled.isEmpty && id == enabled.last) {
                        save(enabled.filter { $0 != id })
                    }
                }
            }
            ForEach(Array(disabled.enumerated()), id: \.element.value) { index, option in
                row(option, on: false, state: .init(), last: last && index == disabled.count - 1) {
                    save(enabled + [option.value])
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, -Space.s2)
    }

    private func row(_ option: SuiteSchema.Field.Option, on: Bool, state: ReorderItemState, last: Bool,
                     toggle: @escaping () -> Void) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(on ? NL.iconTertiary : .clear)
                .frame(width: Size.iconSm)
            if let symbol = option.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(on ? NL.iconPrimary : NL.iconTertiary)
                    .frame(width: Size.iconMd)
            }
            Text(option.title)
                .nlType(.bodySm)
                .foregroundStyle(on ? NL.textPrimary : NL.textSecondary)
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { on }, set: { _ in toggle() }))
                .toggleStyle(NLSwitchStyle())
                .accessibilityLabel(option.title)
        }
        .padding(.horizontal, Space.s2)
        .frame(height: Size.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(state.dragging ? NL.control : .clear)
                .shadow(color: .black.opacity(state.dragging ? 0.25 : 0), radius: 10, y: 4)
        }
        .overlay(alignment: .bottom) {
            if !last, !state.dragging { NL.borderSubtle.frame(height: 1).padding(.horizontal, Space.s2) }
        }
        .scaleEffect(state.dragging ? 1.02 : 1)
        .animation(Motion.spring, value: state)
        .contentShape(Rectangle())
    }

    private func save(_ list: [String]) {
        withMotion(Motion.spring) { model.set(app, field.key, .array(list.map { .string($0) })) }
    }
}

// MARK: - горячая клавиша

/// Кнопка с текущим сочетанием; нажали - ждёт клавиш. Нужен хотя бы один из ⌃⌥⌘,
/// иначе клавиша перехватывала бы обычный набор текста. Esc - отмена. Крестик убирает сочетание.
private struct HotKeyRecorder: View {
    let keyCode: Int
    let modifiers: [String]
    let save: (Int, [String]) -> Void
    @State private var capturing = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: Space.s1) {
            if capturing {
                Button("Нажмите сочетание…") { stop() }
                    .nlButton(.secondary)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(NL.borderFocus, lineWidth: 1)
                    }
                    .help("Сочетание с ⌃, ⌥ или ⌘. Esc - отмена.")
            } else {
                Button { start() } label: {
                    if modifiers.isEmpty {
                        Text("Задать").foregroundStyle(NL.textSecondary)
                    } else {
                        // Каждая клавиша - отдельным колпачком.
                        HStack(spacing: 3) {
                            ForEach(KeyNames.keys(keyCode: keyCode, modifiers: modifiers), id: \.self) { key in
                                Text(key)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(NL.textPrimary)
                                    .padding(.horizontal, 5)
                                    .frame(minWidth: 20, minHeight: 20)
                                    .background(NL.subtle, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            }
                        }
                        .padding(.horizontal, -4)
                    }
                }
                .nlButton(.secondary)
                .help("Нажмите, чтобы задать сочетание")
            }
            Button { save(keyCode, []) } label: {
                Label("Убрать", systemImage: "xmark")
            }
            .nlIconButton(.md)
            .help("Убрать сочетание")
            .disabled(modifiers.isEmpty || capturing)
        }
        .onDisappear { stop() }
    }

    private func start() {
        capturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = Int(event.keyCode)
            let names = KeyNames.modifiers(event.modifierFlags)
            MainActor.assumeIsolated {
                if code == kVK_Escape { stop(); return }
                guard names.contains(where: { $0 != "shift" }) else { NSSound.beep(); return }
                save(code, names)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        capturing = false
    }
}
