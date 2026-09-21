import AppKit
import SwiftUI

/// Обычное окно со значком в Dock. Закрыли окно - приложение выходит: жить в фоне хабу незачем.
@main
struct HubApp: App {
    @NSApplicationDelegateAdaptor private var delegate: HubDelegate
    @State private var model = HubModel()

    var body: some Scene {
        Window("Hub Settings", id: "main") {
            HubView(model: model)
                .frame(minWidth: 1060, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
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
