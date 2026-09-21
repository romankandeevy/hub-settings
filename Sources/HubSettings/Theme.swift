import AppKit
import SwiftUI

// Тема хаба. Каркас (шкала шрифта, отступы, движение, имена) - от Northline v2,
// как во Flow Local; цвета и скругления - системные Apple, как в Системных настройках.
// В коде экранов - только эти имена, никаких «сырых» цветов и размеров шрифта.

// MARK: - цвет

private func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        (appearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua) == .darkAqua ? dark : light
    })
}

private func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha)
}

private func black(_ a: CGFloat) -> NSColor { NSColor(srgbRed: 0, green: 0, blue: 0, alpha: a) }
private func white(_ a: CGFloat) -> NSColor { NSColor(srgbRed: 1, green: 1, blue: 1, alpha: a) }

/// Семантические цвета. Имена - из Northline (на них написаны компоненты), значения - системные цвета Apple:
/// systemBlue/Green/Orange/Red, серые окна macOS, подписи label / secondaryLabel / tertiaryLabel.
enum NL {
    // Фоны
    /// Колонка приложений: прозрачная, под ней системный материал sidebar.
    static let canvas = Color.clear
    static let surface = dynamic(hex(0xECECEC), hex(0x1E1E1E))
    /// Карточка группы, как в Системных настройках.
    static let card = dynamic(hex(0xFFFFFF), white(0.05))
    static let subtle = dynamic(black(0.06), white(0.08))
    static let hover = dynamic(black(0.05), white(0.07))
    static let active = dynamic(black(0.10), white(0.12))
    static let selected = dynamic(hex(0x007AFF), hex(0x0A84FF))
    static let disabled = dynamic(black(0.04), white(0.05))
    /// Кнопка secondary и выбранный сегмент.
    static let control = dynamic(hex(0xFFFFFF), white(0.12))

    static let accent = dynamic(hex(0x007AFF), hex(0x0A84FF))
    static let accentHover = dynamic(hex(0x1A87FF), hex(0x2B95FF))
    static let accentActive = dynamic(hex(0x0068D9), hex(0x0974E0))
    static let accentSubtle = dynamic(hex(0x007AFF, 0.12), hex(0x0A84FF, 0.18))

    static let success = dynamic(hex(0x34C759), hex(0x30D158))
    static let warning = dynamic(hex(0xFF9500), hex(0xFF9F0A))
    static let danger = dynamic(hex(0xFF3B30), hex(0xFF453A))
    static let dangerHover = dynamic(hex(0xFF5147), hex(0xFF5C52))
    static let dangerActive = dynamic(hex(0xE0342A), hex(0xE03D33))
    static let purple = dynamic(hex(0xAF52DE), hex(0xBF5AF2))
    static let pink = dynamic(hex(0xFF2D55), hex(0xFF375F))
    static let teal = dynamic(hex(0x30B0C7), hex(0x40C8E0))
    static let indigo = dynamic(hex(0x5856D6), hex(0x5E5CE6))

    // Текст: label, secondaryLabel, tertiaryLabel
    static let textPrimary = dynamic(black(0.85), white(0.88))
    static let textSecondary = dynamic(black(0.55), white(0.58))
    static let textTertiary = dynamic(black(0.42), white(0.42))
    static let textDisabled = dynamic(black(0.25), white(0.25))
    static let textOnAccent = Color.white
    static let textAccent = accent

    static let iconPrimary = textPrimary
    static let iconSecondary = textSecondary
    static let iconTertiary = textTertiary
    static let iconAccent = accent

    // Границы: 1pt, полупрозрачные
    static let border = dynamic(black(0.10), white(0.10))
    static let borderSubtle = dynamic(black(0.07), white(0.07))
    static let borderStrong = dynamic(black(0.20), white(0.24))
    static let borderHover = dynamic(black(0.16), white(0.18))
    static let borderFocus = accent
    static let ringFocus = dynamic(hex(0x007AFF, 0.35), hex(0x0A84FF, 0.45))

    static let raisedHighlight = dynamic(white(0), white(0.06))
}

// MARK: - шрифт

/// Шкала Northline: размер / межстрочный / трекинг / насыщенность. Один
/// шрифт на всё - системный; моно - только для цифр и сочетаний клавиш.
enum NLType {
    case display, headingLg, heading, headingSm, headingXs
    case bodyLg, body, bodySm, label, labelSm, caption, labelXs, overline, numeric

    var size: CGFloat {
        switch self {
        case .display: return 40
        case .headingLg: return 24
        case .heading: return 26
        case .headingSm, .bodyLg: return 16
        case .headingXs, .body, .numeric: return 14
        case .bodySm, .label: return 13
        case .labelSm, .caption: return 12
        case .labelXs, .overline: return 11
        }
    }

    var lineHeight: CGFloat {
        switch self {
        case .display: return 44
        case .headingLg: return 28.8
        case .heading: return 31
        case .headingSm: return 22.4
        case .bodyLg: return 24.8
        case .headingXs: return 19.6
        case .body, .numeric: return 21.7
        case .bodySm: return 19.5
        case .label: return 15.6
        case .labelSm: return 14.4
        case .caption: return 16.8
        case .labelXs, .overline: return 13.2
        }
    }

    /// Трекинг в em, как в tokens.json.
    var trackingEm: CGFloat {
        switch self {
        case .display: return -0.02
        case .headingLg: return -0.015
        case .heading: return -0.01
        case .headingSm, .headingXs: return -0.005
        case .labelSm: return 0.005
        case .labelXs: return 0.01
        case .overline: return 0.04
        default: return 0
        }
    }

    var weight: Font.Weight {
        switch self {
        case .heading: return .bold
        case .display, .headingLg, .headingSm, .headingXs: return .semibold
        case .label, .labelSm, .labelXs, .overline: return .medium
        default: return .regular
        }
    }

    var font: Font {
        self == .numeric
            ? .system(size: size, weight: weight, design: .monospaced)
            : .system(size: size, weight: weight)
    }
}

extension View {
    /// Стиль текста из шкалы: шрифт, трекинг и межстрочный разом.
    func nlType(_ style: NLType) -> some View {
        font(style.font)
            .tracking(style.size * style.trackingEm)
            .lineSpacing(max(0, style.lineHeight - style.size * 1.2))
            .textCase(style == .overline ? .uppercase : nil)
    }
}

// MARK: - отступы, радиусы, размеры

/// Шаг 4pt. На экран - два ритма: плотный внутри группы (stackSm) и
/// свободный между группами (stackLg).
enum Space {
    static let s0_5: CGFloat = 2
    static let s1: CGFloat = 4
    static let s1_5: CGFloat = 6
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s12: CGFloat = 48

    static let insetSm: CGFloat = 12
    static let insetMd: CGFloat = 16
    static let insetLg: CGFloat = 20
    static let stackXs: CGFloat = 4
    static let stackSm: CGFloat = 8
    static let stackMd: CGFloat = 16
    static let stackLg: CGFloat = 24
    static let inlineSm: CGFloat = 8
    static let inlineMd: CGFloat = 12
    /// Поля страницы в приложении.
    static let page: CGFloat = 24
    static let contentMax: CGFloat = 720
}

enum Radius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 18
}

enum Size {
    static let controlSm: CGFloat = 28
    static let controlMd: CGFloat = 32
    static let control2xs: CGFloat = 20
    static let iconSm: CGFloat = 16
    static let iconMd: CGFloat = 20
    static let iconXl: CGFloat = 32
    static let rowHeight: CGFloat = 44
    static let sidebar: CGFloat = 220
}

// MARK: - тени

/// Тени Northline: нейтральные, двуслойные, размытие не больше 24pt. У
/// карточки тени нет никогда - только у всплывающего.
enum NLShadow { case xs, md, lg, xl }

extension View {
    @ViewBuilder
    func nlShadow(_ level: NLShadow) -> some View {
        switch level {
        case .xs:
            shadow(color: .black.opacity(0.06), radius: 1, y: 1)
        case .md:
            shadow(color: .black.opacity(0.08), radius: 2, y: 2)
                .shadow(color: .black.opacity(0.10), radius: 4, y: 4)
        case .lg:
            shadow(color: .black.opacity(0.10), radius: 4, y: 4)
                .shadow(color: .black.opacity(0.16), radius: 8, y: 8)
        case .xl:
            shadow(color: .black.opacity(0.12), radius: 8, y: 8)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 16)
        }
    }
}

// MARK: - поверхности

extension View {
    /// Карточка/регион: surface + граница 1pt, radius-lg, без тени.
    func nlCard(padding: CGFloat? = Space.insetLg) -> some View {
        self.padding(padding ?? 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NL.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(NL.border, lineWidth: 1)
            }
    }

    /// Всплывающее: surface + граница + тень уровня и блик сверху в тёмной теме.
    func nlRaised(_ level: NLShadow, radius: CGFloat = Radius.lg) -> some View {
        background(NL.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(NL.border, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                NL.raisedHighlight.frame(height: 1).padding(.horizontal, radius)
            }
            .nlShadow(level)
    }
}

// MARK: - движение

/// 100 мс - наведение и нажатие, 150 - фокус и подсказки, 200 - меню,
/// 300 - окна. Всегда ease-out на вход; ничего не пружинит и не растёт больше 1.
enum Motion {
    static let fast = Animation.easeOut(duration: 0.10)
    static let base = Animation.easeOut(duration: 0.15)
    static let moderate = Animation.easeOut(duration: 0.20)
    static let slow = Animation.easeOut(duration: 0.30)
    /// Перестановка и размеры превью: мягкая пружина без заметного отскока, как у самого острова.
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
    /// Чистая смена положения (индикатор вкладки).
    static let position = Animation.easeInOut(duration: 0.20)
}

extension View {
    func motion<V: Equatable>(_ animation: Animation = Motion.moderate, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

/// withAnimation с оглядкой на «Уменьшить движение».
func withMotion<Result>(_ animation: Animation = Motion.moderate, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation, body)
}
