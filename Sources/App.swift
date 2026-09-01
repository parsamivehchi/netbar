import SwiftUI

// File-scope global, not @State: the CommandLineTools toolchain has no SwiftUIMacros
// plugin (macOS 27 SDK makes @State a macro), and a lazily-initialized MainActor global
// is initialized exactly once regardless of App struct lifecycle.
@MainActor private let sharedModel = AppViewModel()

@main
struct NetBarApp: App {
    private var model: AppViewModel { sharedModel }

    var body: some Scene {
        // Menu bar only - no window, no Dock icon (LSUIElement: true)
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            Group {
                if model.barStyle == .stacked {
                    // An image label is the ONLY way to stack two lines: MenuBarExtra
                    // flattens its label to a single text line (verified on macOS 27 -
                    // a VStack of two Texts renders only the first line).
                    Image(nsImage: model.labelImage)
                } else {
                    Text(model.label)
                        .font(.system(size: 12))
                        .monospacedDigit()
                }
            }
            .accessibilityLabel(Text(model.label))
            .task { model.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
