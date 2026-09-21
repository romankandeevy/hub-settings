import AppKit
import SwiftUI

// Примитивы Northline для SwiftUI (те же, что во Flow Local): кнопки,
// переключатель, выпадающий выбор, сегменты, карточка раздела и строка настройки.

// MARK: - кнопки

/// .btn: primary - одно главное действие на экран, secondary - остальное,
/// ghost - второстепенное и иконки, danger - разрушительное. Состояния
/// меняют только фон и границу.
struct NLButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, danger }
    enum Scale { case sm, md }

    var kind: Kind = .secondary
    var scale: Scale = .md
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        NLButtonBody(configuration: configuration, kind: kind, scale: scale, iconOnly: iconOnly)
    }
}

private struct NLButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: NLButtonStyle.Kind
    let scale: NLButtonStyle.Scale
    let iconOnly: Bool
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    var body: some View {
        let height = scale == .sm ? Size.controlSm : Size.controlMd
        let radius = scale == .sm ? Radius.sm : Radius.md
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .labelStyle(NLButtonLabelStyle(iconOnly: iconOnly))
            .nlType(scale == .sm ? .labelSm : .label)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, iconOnly ? 0 : (scale == .sm ? Space.s2 : Space.s3))
            .frame(minWidth: iconOnly ? height : nil)
            .frame(height: height)
            .background(background, in: shape)
            .overlay { shape.strokeBorder(border, lineWidth: 1) }
            .shadow(color: kind == .secondary && enabled ? .black.opacity(0.04) : .clear, radius: 1, y: 1)
            .contentShape(shape)
            .onHover { hover = $0 && enabled }
            .animation(Motion.fast, value: hover)
            .animation(Motion.fast, value: configuration.isPressed)
    }

    private var pressed: Bool { configuration.isPressed && enabled }

    private var background: Color {
        guard enabled else { return kind == .ghost ? .clear : NL.disabled }
        switch kind {
        case .primary: return pressed ? NL.accentActive : hover ? NL.accentHover : NL.accent
        case .danger: return pressed ? NL.dangerActive : hover ? NL.dangerHover : NL.danger
        case .secondary: return pressed ? NL.active : hover ? NL.hover : NL.control
        case .ghost: return pressed ? NL.active : hover ? NL.hover : .clear
        }
    }

    private var foreground: Color {
        guard enabled else { return NL.textDisabled }
        switch kind {
        case .primary, .danger: return NL.textOnAccent
        case .secondary: return NL.textPrimary
        case .ghost: return iconOnly ? NL.iconSecondary : NL.textPrimary
        }
    }

    private var border: Color {
        guard kind == .secondary else { return .clear }
        if !enabled { return NL.borderSubtle }
        return hover ? NL.borderHover : NL.border
    }
}

/// Иконка 16pt и подпись через 6pt; у кнопки-иконки подпись уходит в
/// доступность.
private struct NLButtonLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
                .font(.system(size: 13, weight: .regular))
                .frame(width: Size.iconSm, height: Size.iconSm)
        } else {
            HStack(spacing: Space.s1_5) {
                configuration.icon.font(.system(size: 12, weight: .regular))
                configuration.title
            }
        }
    }
}

extension View {
    func nlButton(_ kind: NLButtonStyle.Kind = .secondary, _ scale: NLButtonStyle.Scale = .md) -> some View {
        buttonStyle(NLButtonStyle(kind: kind, scale: scale))
    }

    func nlIconButton(_ scale: NLButtonStyle.Scale = .sm) -> some View {
        buttonStyle(NLButtonStyle(kind: .ghost, scale: scale, iconOnly: true))
    }
}

/// .btn--link: текст-ссылка акцентного цвета.
struct NLLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LinkBody(configuration: configuration)
    }

    private struct LinkBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hover = false
        var body: some View {
            configuration.label
                .nlType(.label)
                .foregroundStyle(NL.textAccent)
                .underline(hover)
                .contentShape(Rectangle())
                .onHover { hover = $0 }
        }
    }
}

// MARK: - переключатель

/// .switch: дорожка 32×20, ручка 16, вкл. - акцент. В строках настроек
/// подпись несёт сама строка, у переключателя она скрыта.
struct NLSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SwitchBody(configuration: configuration)
    }

    private struct SwitchBody: View {
        let configuration: ToggleStyleConfiguration
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            HStack(alignment: .center, spacing: Space.s3) {
                configuration.label
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? NL.accent : NL.borderStrong)
                    Circle()
                        .fill(configuration.isOn ? Color.white : NL.surface)
                        .frame(width: Size.iconSm, height: Size.iconSm)
                        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                        .padding(Space.s0_5)
                }
                .frame(width: Size.controlMd, height: Size.control2xs)
                .opacity(enabled ? 1 : 0.5)
                .animation(Motion.base, value: configuration.isOn)
                .contentShape(Capsule())
                .onTapGesture { if enabled { configuration.isOn.toggle() } }
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(configuration.isOn ? "Включено" : "Выключено")
                .accessibilityAction { configuration.isOn.toggle() }
            }
        }
    }
}

// MARK: - выбор из списка

/// .select: кнопка secondary с текущим значением и шевроном, по нажатию -
/// системное меню (оно и есть всплывающий слой, со своей тенью).
struct NLSelect<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var dividerAfterFirst = false
    var width: CGFloat? = nil

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
                if dividerAfterFirst && index == 0 { Divider() }
            }
        } label: {
            HStack(spacing: Space.s2) {
                Text(options.first { $0.value == selection }?.title ?? "—")
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NL.iconTertiary)
            }
            .frame(width: width)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(NLButtonStyle(kind: .secondary))
        .fixedSize()
    }
}

// MARK: - строки и карточки

struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    var detailColor: Color = NL.textTertiary
    var last = false
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s0_5) {
                Text(title)
                    .nlType(.bodySm)
                    .foregroundStyle(NL.textPrimary)
                if let detail {
                    Text(detail)
                        .nlType(.caption)
                        .foregroundStyle(detailColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .padding(.vertical, Space.s3)
        .frame(minHeight: Size.rowHeight)
        .overlay(alignment: .bottom) {
            if !last { NL.borderSubtle.frame(height: 1) }
        }
    }
}

/// .kv-row: ключ третичным, значение - основным, цифры моноширинные.
struct FormFooter: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .nlType(.caption)
            .foregroundStyle(NL.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}


/// Карточка раздела: заголовок heading-xs, строки внутри, пояснение под
/// карточкой.
struct SettingsCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.stackSm) {
            VStack(alignment: .leading, spacing: 0) {
                if let title {
                    Text(title)
                        .nlType(.headingXs)
                        .foregroundStyle(NL.textPrimary)
                        .padding(.top, Space.insetMd)
                        .padding(.bottom, Space.s1)
                }
                content()
            }
            .padding(.horizontal, Space.insetMd)
            .background(NL.card, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(NL.border, lineWidth: 1)
            }
            if let footer { FormFooter(footer) }
        }
    }
}

/// .segmented: подложка subtle, выбранный сегмент - surface с тенью xs.
struct Segmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    var body: some View {
        HStack(spacing: Space.s0_5) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.value == selection
                Button { withMotion(Motion.fast) { selection = option.value } } label: {
                    Text(option.title)
                        .nlType(.labelSm)
                        .foregroundStyle(on ? NL.textPrimary : NL.textSecondary)
                        .padding(.horizontal, Space.s3)
                        .frame(height: 24)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(NL.control)
                                    .nlShadow(.xs)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(Space.s0_5)
        .background(NL.subtle, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .fixedSize()
    }
}
