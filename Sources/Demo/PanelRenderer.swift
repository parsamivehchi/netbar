import AppKit
import SwiftUI

/// Renders PanelView into a PNG without a window. Materials do not exist outside a
/// window, so the popover chrome is stood in by an opaque rounded dark surface.
@MainActor
enum PanelRenderer {
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
