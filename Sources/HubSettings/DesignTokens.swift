import AppKit
import SwiftUI

// Дизайн-токены окна настроек. Всё как в Системных настройках macOS: только системные шрифты и цвета
// (они сами подстраиваются под светлую и тёмную тему и под акцентный цвет системы), размеры - по их окну.
// В коде экранов - только эти имена, никаких «сырых» чисел, цветов и шрифтов.

// MARK: - окно

enum WindowMetrics {
    /// Размер при первом запуске; дальше окно помнит свой.
    static let defaultSize = CGSize(width: 960, height: 680)
    static let minSize = CGSize(width: 760, height: 480)
    static let frameAutosaveName = "HubSettingsWindow"
}

/// Верх окна: поиск и вкладки приложений.
enum TopBarMetrics {
    /// Под кнопками окна: заголовок скрыт, поиск стоит на его месте.
    static let top: CGFloat = 10
    static let trafficLightsInset: CGFloat = 80
    static let searchWidth: CGFloat = 460
    static let searchHeight: CGFloat = 30
    static let searchRadius: CGFloat = 8
    static let tabHeight: CGFloat = 28
    static let tabRadius: CGFloat = 7
}

/// Экран приложения: список страниц слева и форма справа.
enum ScreenMetrics {
    static let listWidth: CGFloat = 230
    /// Форма не растягивается на всю ширину большого окна.
    static let formMaxWidth: CGFloat = 680
}

// MARK: - значок модуля

/// Белый символ SF Symbols в цветном скруглённом квадрате (continuous), как у разделов Системных настроек.
enum TileMetrics {
    struct Size {
        let side: CGFloat
        let radius: CGFloat
        let symbol: CGFloat
    }

    /// Во вкладке приложения сверху.
    static let tab = Size(side: 18, radius: 4.5, symbol: 10)
    /// В боковом списке.
    static let sidebar = Size(side: 20, radius: 5, symbol: 11)
    /// В результатах поиска и в списке модулей на экране «Основные».
    static let row = Size(side: 22, radius: 5.5, symbol: 12)
    /// В шапке экрана модуля.
    static let header = Size(side: 44, radius: 10, symbol: 22)
    /// Шапка подстраницы - чуть скромнее шапки модуля.
    static let pageHeader = Size(side: 36, radius: 8.5, symbol: 18)
}

/// Цвета плиток: системные цвета, у каждого модуля свой.
enum TileColor {
    static let gray = Color(nsColor: .systemGray)
    static let blue = Color(nsColor: .systemBlue)
    static let indigo = Color(nsColor: .systemIndigo)
    static let purple = Color(nsColor: .systemPurple)
    static let pink = Color(nsColor: .systemPink)
    static let red = Color(nsColor: .systemRed)
    static let orange = Color(nsColor: .systemOrange)
    static let yellow = Color(nsColor: .systemYellow)
    static let green = Color(nsColor: .systemGreen)
    static let mint = Color(nsColor: .systemMint)
    static let teal = Color(nsColor: .systemTeal)
    static let cyan = Color(nsColor: .systemCyan)
    static let brown = Color(nsColor: .systemBrown)

    /// Для модулей без своего цвета: выбирается по имени, так что у модуля он всегда один и тот же.
    static let fallback = [blue, green, orange, purple, teal, pink, indigo, mint, red, cyan, brown, yellow]

    static func stable(for id: String) -> Color {
        // Свой хеш, а не hashValue: тот меняется от запуска к запуску.
        let sum = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return fallback[sum % fallback.count]
    }
}

// MARK: - текст

/// Только системный шрифт в системных стилях: размер следует настройкам macOS.
enum TextStyle {
    static let tab = Font.callout.weight(.medium)
    static let shortcut = Font.caption.weight(.medium)
    static let childTitle = Font.body.weight(.medium)
    static let headerTitle = Font.title2.weight(.semibold)
    static let headerSummary = Font.callout
    static let pageTitle = Font.title3.weight(.semibold)
    static let chevron = Font.system(size: 12, weight: .semibold)
    static let sidebarStatus = Font.caption
    static let searchResultTitle = Font.body
    static let searchResultPath = Font.caption
    static let footer = Font.subheadline
    static let value = Font.body.monospacedDigit()
    static let keyCap = Font.body.weight(.medium)
    static let back = Font.callout
    static let pageTile = Font.body
    static let emptyTitle = Font.title3.weight(.semibold)
    static let emptyMessage = Font.callout
}

// MARK: - отступы

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 24

    /// Между плиткой и подписью в строке списка.
    static let tileLabel: CGFloat = 8
    /// Между крупной плиткой шапки и её текстом.
    static let headerTile: CGFloat = 14
    /// Вертикальные поля шапки модуля.
    static let headerVertical: CGFloat = 6
}

// MARK: - контролы

enum ControlMetrics {
    /// Переключатели в строках - маленькие, как в Системных настройках.
    static let switchSize = ControlSize.mini
    static let sliderWidth: CGFloat = 180
    static let textFieldWidth: CGFloat = 220
    /// Под значение справа от ползунка: «1280 пикс.» помещается, колонка не прыгает.
    static let sliderValueWidth: CGFloat = 64
    static let swatch: CGFloat = 16
    static let swatchRing: CGFloat = 2
    static let swatchSpacing: CGFloat = 6
    static let hotkeyMinWidth: CGFloat = 120
    static let hotkeyHeight: CGFloat = 22
    static let hotkeyRadius: CGFloat = 6
    static let listSymbolWidth: CGFloat = 20
    static let dragHandleWidth: CGFloat = 14
    static let listRowHeight: CGFloat = 32
    /// Высота живого превью в первой секции модуля.
    static let previewHeight: CGFloat = 340
    static let previewRadius: CGFloat = 8
    /// Превью в шапке экрана.
    static let heroRadius: CGFloat = 12
    /// Плитки разделов в сетке.
    static let pageTileMin: CGFloat = 180
    static let pageTileHeight: CGFloat = 40
}

// MARK: - цвета

/// Только системные цвета: подписи, разделители, фоны контролов и акцент, выбранный в Системных настройках.
enum Palette {
    static let accent = Color.accentColor
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let listBackground = Color.primary.opacity(0.025)
    static let fieldFill = Color.primary.opacity(0.06)
    static let hairline = Color.primary.opacity(0.08)
    static let tabSelected = Color.primary.opacity(0.09)
    static let tileSymbol = Color.white
    static let separator = Color(nsColor: .separatorColor)
    static let controlBackground = Color(nsColor: .controlBackgroundColor)
    static let keyCapBackground = Color(nsColor: .quaternaryLabelColor)
    static let placeholder = Color(nsColor: .placeholderTextColor)
    static let highlight = Color.accentColor.opacity(0.18)
    /// Строка-ссылка на подстраницу под курсором и нажатая.
    static let rowHover = Color.primary.opacity(0.05)
    static let tileFill = Color.primary.opacity(0.05)
    static let tileHover = Color.primary.opacity(0.1)
    static let running = Color(nsColor: .systemGreen)
    static let stopped = Color.primary.opacity(0.2)
    static let rowPressed = Color.primary.opacity(0.1)
    static let dragShadow = Color.black.opacity(0.2)
    /// Тонкая обводка плитки, чтобы светлые цвета не терялись на светлом фоне.
    static let tileStroke = Color.primary.opacity(0.08)
    static let selectedSwatchRing = Color.primary
}

/// Выключенный модуль: настройки видны, но приглушены и не нажимаются.
enum DisabledStyle {
    static let opacity: Double = 0.45
}

// MARK: - движение

/// Движение как у системы: коротко и без отскока. С «Уменьшить движение» всё мгновенно.
enum Motion {
    static let fast = Animation.easeOut(duration: 0.12)
    static let base = Animation.easeOut(duration: 0.18)
    /// Смена экрана модуля: мягкое затухание, без сдвигов.
    static let page = Animation.easeInOut(duration: 0.2)
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.86)
    /// Сколько держится подсветка найденной настройки.
    static let highlightDuration: Duration = .seconds(1.6)
    static let highlightFade = Animation.easeOut(duration: 0.6)
}

extension View {
    func motion<V: Equatable>(_ animation: Animation = Motion.base, value: V) -> some View {
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
func withMotion<Result>(_ animation: Animation = Motion.base, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation, body)
}

// MARK: - чёрное стекло

/// Окно всегда тёмное, как сам остров: размытие рабочего стола под глубоким чёрным, белый текст,
/// никаких системных синих - переключатели и выделение белые и серые.
enum Glass {
    static let tint = Color.black.opacity(0.62)
    static let card = Color.white.opacity(0.045)
    static let cardStroke = Color.white.opacity(0.07)
    static let tile = Color.white.opacity(0.09)
    static let tileStroke = Color.white.opacity(0.1)
    static let selected = Color.white.opacity(0.11)
    static let hover = Color.white.opacity(0.05)
    static let switchOn = Color.white
    static let switchOff = Color.white.opacity(0.16)
    static let knobOn = Color.black
    static let knobOff = Color.white.opacity(0.85)
    /// Ползунки, выбор и прочие системные контролы - серым.
    static let controlTint = Color(white: 0.72)
}

/// Подложка окна: размытие того, что под окном, и чёрный поверх.
struct GlassBackground: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {}
}

/// Переключатель в духе острова: включён - белая дорожка с чёрной ручкой, выключен - едва заметная.
struct GlassSwitch: ToggleStyle {
    @Environment(\.controlSize) private var size
    @Environment(\.isEnabled) private var enabled
    @Environment(\.switchOnly) private var switchOnly

    func makeBody(configuration: Configuration) -> some View {
        let height: CGFloat = switch size {
        case .mini: 14
        case .small: 18
        default: 22
        }
        let width = height * 1.75
        return HStack {
            if !switchOnly {
                configuration.label
                Spacer(minLength: Spacing.md)
            }
            Capsule()
                .fill(configuration.isOn ? Glass.switchOn : Glass.switchOff)
                .frame(width: width, height: height)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? Glass.knobOn : Glass.knobOff)
                        .padding(2)
                        .frame(width: height, height: height)
                }
                .opacity(enabled ? 1 : 0.4)
                .contentShape(Capsule())
                .onTapGesture { withMotion(Motion.spring) { configuration.isOn.toggle() } }
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(configuration.isOn ? "Вкл." : "Выкл.")
        }
    }
}

extension EnvironmentValues {
    /// Только сам переключатель, без подписи (`labelsHidden` своему стилю не виден на macOS 14).
    @Entry var switchOnly = false
}

extension View {
    func switchOnly() -> some View { environment(\.switchOnly, true).labelsHidden() }
}
