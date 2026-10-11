import AppKit
import SwiftUI

/// Обычное окно со значком в Dock. Закрыли окно - приложение выходит: жить в фоне хабу незачем.
@main
struct HubApp: App {
    @NSApplicationDelegateAdaptor private var delegate: HubDelegate
    @State private var model = HubModel()
    @State private var apps = AppMonitor()

    var body: some Scene {
        Window("Hub Settings", id: "main") {
            HubView(model: model, apps: apps)
                .frame(minWidth: WindowMetrics.minSize.width, minHeight: WindowMetrics.minSize.height)
                .background(WindowFrameAutosave(name: WindowMetrics.frameAutosaveName))
        }
        .defaultSize(WindowMetrics.defaultSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .undoRedo) {
                Button("Отменить") { withMotion(Motion.spring) { model.undo() } }
                    .keyboardShortcut("z")
                    .disabled(model.undoCount == 0)
                Button("Повторить") { withMotion(Motion.spring) { model.redo() } }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(model.redoCount == 0)
            }
        }
    }
}

final class HubDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}

/// Окно помнит свой размер и место между запусками (последний модуль помнит `HubModel.selection`).
private struct WindowFrameAutosave: NSViewRepresentable {
    let name: String

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // Чёрное стекло: окно прозрачное, фон рисует размытие под ним.
            window.isOpaque = false
            window.backgroundColor = .clear
            window.appearance = NSAppearance(named: .darkAqua)
            window.setFrameUsingName(name)
            window.setFrameAutosaveName(name)
        }
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}
}
