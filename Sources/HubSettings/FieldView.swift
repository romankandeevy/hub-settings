import AppKit
import Carbon.HIToolbox
import SuiteKit
import SwiftUI

/// Строка формы для одного поля схемы - на нативных контролах, как в Системных настройках:
/// переключатель, выбор, ползунок со значением справа, цвет, сочетание клавиш, список с перетаскиванием.
/// Любое изменение сразу пишется в файл настроек приложения; кнопки «Сохранить» нет.
struct FieldRow: View {
    let model: HubModel
    let app: String
    let field: SuiteSchema.Field
    let copy: FieldCopy

    var body: some View {
        switch field.kind {
        case .toggle:
            Toggle(isOn: Binding(
                get: { model.value(app, field.key)?.bool ?? false },
                set: { on in withMotion { model.set(app, field.key, .bool(on)) } }
            )) { label }
            .toggleStyle(GlassSwitch())
            .controlSize(ControlMetrics.switchSize)
        case .number:
            LabeledContent {
                NumberControl(field: field, format: copy.value, value: Binding(
                    get: { model.value(app, field.key)?.number ?? field.min ?? 0 },
                    set: { model.set(app, field.key, .number($0)) }
                ))
            } label: { label }
        case .choice:
            ChoiceControl(field: field, selection: Binding(
                get: { model.value(app, field.key)?.string ?? "" },
                set: { value in withMotion { model.set(app, field.key, .string(value)) } }
            )) { label }
        case .hotkey:
            LabeledContent {
                HotKeyRecorder(
                    title: copy.title,
                    keyCode: Int(model.value(app, field.key)?.number ?? 0),
                    modifiers: model.value(app, field.modifiersKey ?? "")?.strings ?? []
                ) { code, modifiers in
                    model.set(app, field.key, .number(Double(code)))
                    if let key = field.modifiersKey { model.set(app, key, .array(modifiers.map { .string($0) })) }
                }
            } label: { label }
        case .color:
            LabeledContent {
                ColorControl(options: field.options ?? [], value: Binding(
                    get: { model.value(app, field.key)?.string ?? "" },
                    set: { hex in withMotion { model.set(app, field.key, .string(hex)) } }
                ))
            } label: { label }
        case .list:
            OrderedList(model: model, app: app, field: field)
        case .text:
            LabeledContent {
                TextControl(placeholder: field.unit ?? "", value: Binding(
                    get: { model.value(app, field.key)?.string ?? "" },
                    set: { model.set(app, field.key, .string($0)) }
                ))
            } label: { label }
        }
    }

    /// Подпись и, если нужно, строка пояснения под ней: форма сама делает вторую строку серой и мелкой.
    @ViewBuilder
    private var label: some View {
        Text(copy.title)
        if let help = copy.help {
            Text(help)
        }
    }
}

// MARK: - число

/// Ползунок и значение справа. Файл пишется на каждом шаге, так что приложение меняется прямо во время перетаскивания.
private struct NumberControl: View {
    let field: SuiteSchema.Field
    let format: FieldCopy.ValueFormat
    @Binding var value: Double

    var body: some View {
        let low = field.min ?? 0
        let high = max(field.max ?? 1, low)
        let step = field.step ?? 1
        let slider = Binding(get: { min(max(value, low), high) },
                             set: { value = min(max(($0 / step).rounded() * step, low), high) })
        HStack(spacing: Spacing.md) {
            switch format {
            case .ends(let start, let end):
                Slider(value: slider, in: low...high) {
                    Text(field.title)
                } minimumValueLabel: {
                    Text(start)
                } maximumValueLabel: {
                    Text(end)
                }
                .labelsHidden()
                .frame(width: ControlMetrics.sliderWidth + ControlMetrics.sliderValueWidth)
            case .plain, .percent:
                Slider(value: slider, in: low...high)
                    .labelsHidden()
                    .frame(width: ControlMetrics.sliderWidth)
                Text(text(slider.wrappedValue, step: step))
                    .font(TextStyle.value)
                    .foregroundStyle(.secondary)
                    .frame(width: ControlMetrics.sliderValueWidth, alignment: .trailing)
                    .contentTransition(.numericText(value: slider.wrappedValue))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(text(value, step: step))
    }

    private func text(_ value: Double, step: Double) -> String {
        if case .percent = format {
            return "\(Int((value * 100).rounded())) %"
        }
        let digits = step >= 1 ? 0 : step >= 0.1 ? 1 : 2
        let number = value.formatted(.number.precision(.fractionLength(0...digits)).grouping(.never))
        guard let unit = Self.unit(field.unit) else { return number }
        return unit.spaced ? "\(number) \(unit.text)" : "\(number)\(unit.text)"
    }

    /// Единицы из схемы - по-русски и без технических сокращений.
    private static func unit(_ raw: String?) -> (text: String, spaced: Bool)? {
        switch raw {
        case nil, "": nil
        case "pt": ("пт", true)
        case "px": ("пикс.", true)
        case "%": ("%", true)
        case "×", "x": ("×", false)
        case "°": ("°", false)
        case let other?: (other, true)
        }
    }
}

// MARK: - текст

/// Поле ввода. Пишется в файл по Return или когда уходите из поля - не на каждую букву,
/// чтобы приложение не искало город «М», «Мо», «Мос»…
private struct TextControl: View {
    let placeholder: String
    @Binding var value: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder))
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .frame(width: ControlMetrics.textFieldWidth)
            .focused($focused)
            .onSubmit(commit)
            .onAppear { text = value }
            .onChange(of: value) { if !focused { text = value } }
            .onChange(of: focused) { _, now in if !now { commit() } }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != value { value = trimmed }
    }
}

// MARK: - выбор

/// Два-три коротких варианта - сегменты, больше - всплывающее меню, как в Системных настройках.
private struct ChoiceControl<Label: View>: View {
    let field: SuiteSchema.Field
    @Binding var selection: String
    @ViewBuilder let label: () -> Label

    var body: some View {
        let options = field.options ?? []
        let compact = options.count <= 3 && options.map(\.title.count).reduce(0, +) <= 24
        let picker = Picker(selection: $selection) {
            ForEach(options, id: \.value) { option in
                if let symbol = option.symbol, !compact {
                    SwiftUI.Label(option.title, systemImage: symbol).tag(option.value)
                } else {
                    Text(option.title).tag(option.value)
                }
            }
        } label: { label() }
        if compact {
            picker.pickerStyle(.segmented).fixedSize()
        } else {
            picker.pickerStyle(.menu).fixedSize()
        }
    }
}

// MARK: - цвет

/// Образцы кружками, как выбор акцента в Системных настройках, и свой цвет из системной палитры.
/// Значение - строка «#RRGGBB».
private struct ColorControl: View {
    let options: [SuiteSchema.Field.Option]
    @Binding var value: String

    var body: some View {
        HStack(spacing: ControlMetrics.swatchSpacing) {
            ForEach(options, id: \.value) { option in
                let selected = option.value.caseInsensitiveCompare(value) == .orderedSame
                Button { value = option.value } label: {
                    Circle()
                        .fill(Self.color(option.value))
                        .frame(width: ControlMetrics.swatch, height: ControlMetrics.swatch)
                        .overlay { Circle().strokeBorder(Palette.tileStroke, lineWidth: 1) }
                        .padding(ControlMetrics.swatchRing + 1)
                        .overlay {
                            Circle().strokeBorder(selected ? Palette.selectedSwatchRing : .clear,
                                                  lineWidth: ControlMetrics.swatchRing)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(option.title)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
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

/// Включённые варианты сверху - их можно перетаскивать за любое место. Выключенные ниже, в порядке схемы.
/// Переключатель справа убирает и возвращает пункт.
private struct OrderedList: View {
    let model: HubModel
    let app: String
    let field: SuiteSchema.Field

    var body: some View {
        let options = field.options ?? []
        let enabled = (model.value(app, field.key)?.strings ?? []).filter { id in options.contains { $0.value == id } }
        let disabled = options.filter { !enabled.contains($0.value) }
        VStack(spacing: 0) {
            ReorderStrip(axis: .vertical, items: enabled, length: ControlMetrics.listRowHeight, spacing: 0,
                         removeDistance: nil, onChange: save) { id, state in
                if let option = options.first(where: { $0.value == id }) {
                    row(option, on: true, dragging: state.dragging,
                        divider: !(disabled.isEmpty && id == enabled.last)) {
                        save(enabled.filter { $0 != id })
                    }
                }
            }
            ForEach(Array(disabled.enumerated()), id: \.element.value) { index, option in
                row(option, on: false, dragging: false, divider: index < disabled.count - 1) {
                    save(enabled + [option.value])
                }
                .transition(.opacity)
            }
        }
    }

    private func row(_ option: SuiteSchema.Field.Option, on: Bool, dragging: Bool, divider: Bool,
                     toggle: @escaping () -> Void) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(on ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.clear))
                .frame(width: ControlMetrics.dragHandleWidth)
                .accessibilityHidden(true)
            if let symbol = option.symbol {
                Image(systemName: symbol)
                    .foregroundStyle(on ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .frame(width: ControlMetrics.listSymbolWidth)
            }
            Toggle(option.title, isOn: Binding(get: { on }, set: { _ in toggle() }))
                .toggleStyle(GlassSwitch())
                .controlSize(ControlMetrics.switchSize)
                .foregroundStyle(on ? .primary : .secondary)
        }
        .frame(height: ControlMetrics.listRowHeight)
        .background {
            if dragging {
                RoundedRectangle(cornerRadius: ControlMetrics.previewRadius, style: .continuous)
                    .fill(Palette.controlBackground)
                    .shadow(color: Palette.dragShadow, radius: 8, y: 3)
                    .padding(.horizontal, -Spacing.md)
            }
        }
        .overlay(alignment: .bottom) {
            if divider, !dragging { Divider().padding(.leading, ControlMetrics.dragHandleWidth + Spacing.md) }
        }
        .animation(Motion.spring, value: dragging)
        .contentShape(Rectangle())
    }

    private func save(_ list: [String]) {
        withMotion(Motion.spring) { model.set(app, field.key, .array(list.map { .string($0) })) }
    }
}

// MARK: - горячая клавиша

/// Поле сочетания клавиш, как в «Клавиатура → Сочетания клавиш»: нажали - ждёт клавиш (с фокусной рамкой),
/// Esc - отмена, крестик внутри поля убирает сочетание. Нужен хотя бы один из ⌃⌥⌘, иначе клавиша
/// перехватывала бы обычный набор текста.
private struct HotKeyRecorder: View {
    let title: String
    let keyCode: Int
    let modifiers: [String]
    let save: (Int, [String]) -> Void
    @State private var capturing = false
    @State private var monitor: Any?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ControlMetrics.hotkeyRadius, style: .continuous)
        HStack(spacing: Spacing.xs) {
            Group {
                if capturing {
                    Text("Нажмите сочетание")
                        .foregroundStyle(Palette.placeholder)
                } else if modifiers.isEmpty {
                    Text("Не задано")
                        .foregroundStyle(Palette.placeholder)
                } else {
                    Text(KeyNames.shortcut(keyCode: keyCode, modifiers: modifiers))
                        .font(TextStyle.keyCap)
                }
            }
            .frame(maxWidth: .infinity)
            if !modifiers.isEmpty || capturing {
                Button {
                    if capturing { stop() } else { save(keyCode, []) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(capturing ? "Отменить" : "Убрать сочетание")
                .accessibilityLabel(capturing ? "Отменить" : "Убрать сочетание")
            }
        }
        .padding(.horizontal, Spacing.sm)
        .frame(minWidth: ControlMetrics.hotkeyMinWidth, minHeight: ControlMetrics.hotkeyHeight)
        .fixedSize()
        .background(Palette.controlBackground, in: shape)
        .overlay { shape.strokeBorder(Palette.separator, lineWidth: 1) }
        .overlay {
            if capturing { shape.strokeBorder(Palette.accent, lineWidth: 2).padding(-1) }
        }
        .contentShape(shape)
        .onTapGesture { capturing ? stop() : start() }
        .help("Нажмите и введите сочетание с ⌃, ⌥ или ⌘. Esc - отмена.")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(modifiers.isEmpty ? "Не задано" : KeyNames.shortcut(keyCode: keyCode, modifiers: modifiers))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { capturing ? stop() : start() }
        .onDisappear { stop() }
    }

    private func start() {
        capturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = Int(event.keyCode)
            let names = KeyNames.modifiers(event.modifierFlags)
            MainActor.assumeIsolated {
                if code == kVK_Escape { stop(); return }
                // F1-F20 можно и без модификатора: «none» - признак клавиши без ⌃⌥⌘.
                let bare = names.isEmpty && KeyNames.functionKeys.contains(code)
                guard bare || names.contains(where: { $0 != "shift" }) else { NSSound.beep(); return }
                save(code, bare ? ["none"] : names)
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
