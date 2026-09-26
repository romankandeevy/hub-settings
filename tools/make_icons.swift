// Рисует иконки приложений набора в стиле macOS: скруглённый квадрат (continuous) по сетке Apple,
// градиент системного цвета, белый символ SF Symbols, мягкая тень. Кладёт Resources/AppIcon.icns
// в папку каждого приложения. Цвета и символы - те же, что у плиток в Hub Settings.
//
//   swift tools/make_icons.swift            все приложения
//   swift tools/make_icons.swift island     только одно
import AppKit

struct Icon {
    let app: String
    let symbol: String
    /// Верх и низ градиента.
    let top: NSColor
    let bottom: NSColor
    /// Символ немного смещён или уменьшен, если так он смотрится ровнее.
    var scale: CGFloat = 1
}

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let icons = [
    // Как «Системные настройки»: серая шестерёнка.
    Icon(app: "hub-settings", symbol: "gearshape.fill", top: rgb(0x9A9AA0), bottom: rgb(0x5E5E64), scale: 1.05),
    Icon(app: "island", symbol: "island", top: rgb(0x7B79F0), bottom: rgb(0x4644C4)),
    Icon(app: "sidebar", symbol: "sidebar.right", top: rgb(0x3E9BFF), bottom: rgb(0x0060DD)),
    Icon(app: "shelf", symbol: "tray.full.fill", top: rgb(0xFFB340), bottom: rgb(0xFF7A00)),
    Icon(app: "awake", symbol: "cup.and.saucer.fill", top: rgb(0xFFDD4A), bottom: rgb(0xF5A300), scale: 0.95),
]

/// Сетка иконки macOS: на холсте 1024 сам квадрат 824 со скруглением ~185, отступ 100.
func draw(_ icon: Icon, size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let k = size / 1024
    let rect = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 185 * k, yRadius: 185 * k)

    // Тень под квадратом, как у системных иконок.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 20 * k
    shadow.shadowOffset = NSSize(width: 0, height: -10 * k)
    shadow.set()
    icon.bottom.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: icon.top, ending: icon.bottom)!.draw(in: shape, angle: -90)
    // Лёгкий блик сверху и тонкая внутренняя обводка.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.12).setStroke()
    let border = NSBezierPath(roundedRect: rect.insetBy(dx: 1.5 * k, dy: 1.5 * k), xRadius: 184 * k, yRadius: 184 * k)
    border.lineWidth = 3 * k
    border.stroke()

    // Символ: белый, по центру, с мягкой тенью.
    let config = NSImage.SymbolConfiguration(pointSize: 400 * k * icon.scale, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if icon.symbol == "island" {
        // Остров - экран MacBook с чёрной капсулой у верхней кромки.
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        glow.shadowBlurRadius = 14 * k
        glow.shadowOffset = NSSize(width: 0, height: -6 * k)
        glow.set()
        NSColor.white.setFill()
        let screen = NSRect(x: rect.midX - 290 * k, y: rect.midY - 200 * k, width: 580 * k, height: 400 * k)
        NSBezierPath(roundedRect: screen, xRadius: 44 * k, yRadius: 44 * k).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 0.08, alpha: 1).setFill()
        let pill = NSRect(x: rect.midX - 150 * k, y: screen.maxY - 30 * k - 76 * k, width: 300 * k, height: 76 * k)
        NSBezierPath(roundedRect: pill, xRadius: 38 * k, yRadius: 38 * k).fill()
    } else if let glyph = NSImage(systemSymbolName: icon.symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let box = glyph.size
        let fit = min(1, 480 * k * icon.scale / max(box.width, box.height))
        let w = box.width * fit, h = box.height * fit
        let target = NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        glow.shadowBlurRadius = 12 * k
        glow.shadowOffset = NSSize(width: 0, height: -6 * k)
        glow.set()
        glyph.draw(in: target)
        NSGraphicsContext.restoreGraphicsState()
    } else {
        FileHandle.standardError.write("нет символа \(icon.symbol)\n".data(using: .utf8)!)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let apps = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
let only = CommandLine.arguments.dropFirst().first
let temp = FileManager.default.temporaryDirectory

for icon in icons where only == nil || only == icon.app {
    let set = temp.appendingPathComponent("\(icon.app).iconset")
    try? FileManager.default.removeItem(at: set)
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
            let png = draw(icon, size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
            try png.write(to: set.appendingPathComponent(name))
        }
    }
    let out = apps.appendingPathComponent(icon.app).appendingPathComponent("Resources/AppIcon.icns")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", set.path, "-o", out.path]
    try task.run()
    task.waitUntilExit()
    // Картинка 1024 рядом - посмотреть глазами.
    try draw(icon, size: 1024).representation(using: .png, properties: [:])!
        .write(to: temp.appendingPathComponent("\(icon.app).png"))
    print(task.terminationStatus == 0 ? "==> \(out.path)" : "!!! iconutil: \(icon.app)")
}
print("превью: \(temp.path)")
