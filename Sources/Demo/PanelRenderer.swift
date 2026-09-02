import AppKit
import SwiftUI

/// Renders PanelView into a PNG without a window. Materials do not exist outside a
/// window, so the popover chrome is stood in by an opaque rounded dark surface.
@MainActor
enum PanelRenderer {
    /// The stacked menu bar label at 4x on a menu-bar-like dark strip.
    static func renderLabel(model: AppViewModel, to path: String) -> Bool {
        let content = HStack(spacing: 0) {
            Image(nsImage: model.labelImage)
                .renderingMode(.template)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(Color(white: 0.11))
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 4
        return write(renderer, to: path)
    }

    static func render(model: AppViewModel, to path: String) -> Bool {
        let content = PanelView(model: model)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .padding(12)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return write(renderer, to: path)
    }

    private static func write<C: View>(_ renderer: ImageRenderer<C>, to path: String) -> Bool {
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("render failed\n".utf8))
            return false
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
            return true
        } catch {
            FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
            return false
        }
    }
}
