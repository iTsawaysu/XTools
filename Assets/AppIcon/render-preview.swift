// Render the packaged app through macOS so the README includes its native icon surround.
// Usage: swift Assets/AppIcon/render-preview.swift build/XTools.app Assets/AppIcon/XToolsIconPreview.png
import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fatalError("Expected an app bundle path and a PNG output path")
}
let appURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
guard FileManager.default.fileExists(atPath: appURL.appendingPathComponent("Contents/Info.plist").path) else {
    fatalError("Package the app before rendering its icon")
}
let size = 1024
let icon = NSWorkspace.shared.icon(forFile: appURL.path)
icon.size = NSSize(width: size, height: size)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create an icon rendering context")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode the icon preview")
}
try png.write(to: outputURL)
