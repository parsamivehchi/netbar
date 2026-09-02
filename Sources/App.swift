import SwiftUI

// File-scope global, not @State: the CommandLineTools toolchain has no SwiftUIMacros
// plugin (macOS 27 SDK makes @State a macro), and a lazily-initialized MainActor global
// is initialized exactly once regardless of App struct lifecycle.
@MainActor private let sharedModel = AppViewModel()

@main
struct NetBarApp: App {
    private var model: AppViewModel { sharedModel }

    init() {
        // Headless screenshot: NETBAR_DEMO=1 NETBAR_RENDER_PANEL=/abs/out.png NetBar
        // renders the panel on sample data to a 2x PNG and exits before any window,
        // status item, or sampler exists. Used for the README and the product page so
        // no capture is ever taken from a live session (see DemoFixture).
        if let path = DemoFixture.labelRenderPath {
            guard DemoFixture.isActive else { exit(2) }
            exit(PanelRenderer.renderLabel(model: sharedModel, to: path) ? 0 : 1)
        }
        if let path = DemoFixture.renderPath {
            guard DemoFixture.isActive else {
                FileHandle.standardError.write(Data("NETBAR_RENDER_PANEL requires NETBAR_DEMO=1 (never render live data)\n".utf8))
                exit(2)
            }
            exit(PanelRenderer.render(model: sharedModel, to: path) ? 0 : 1)
        }
    }

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
