import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift generate_icon.swift <iconset-directory>\n", stderr)
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in variants {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let side = CGFloat(size)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()

    let inset = max(1, side * 0.045)
    let iconRect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    NSColor(calibratedWhite: 0.035, alpha: 1).setFill()
    NSBezierPath(roundedRect: iconRect, xRadius: side * 0.22, yRadius: side * 0.22).fill()

    let inner = iconRect.insetBy(dx: side * 0.025, dy: side * 0.025)
    NSColor(calibratedWhite: 0.09, alpha: 1).setStroke()
    let border = NSBezierPath(roundedRect: inner, xRadius: side * 0.20, yRadius: side * 0.20)
    border.lineWidth = max(0.5, side * 0.008)
    border.stroke()

    let font = NSFont.systemFont(ofSize: side * 0.225, weight: .black)
    let word = NSMutableAttributedString(
        string: "Fuck",
        attributes: [.font: font, .foregroundColor: NSColor.white]
    )
    word.append(NSAttributedString(
        string: ".",
        attributes: [.font: font, .foregroundColor: NSColor.systemRed]
    ))
    let textSize = word.size()
    let textPoint = NSPoint(x: (side - textSize.width) / 2, y: (side - textSize.height) / 2 + side * 0.012)
    word.draw(at: textPoint)

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    if let png = bitmap.representation(using: .png, properties: [:]) {
        try png.write(to: output.appendingPathComponent(name))
    }
}
