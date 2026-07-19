#!/usr/bin/env swift
import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("usage: make_dmg_background.swift OUTPUT\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 680, height: 360)
let image = NSImage(size: size)
image.lockFocus()

// Finder owns the app names below each icon. Keep one neutral plane so its
// native 12 pt labels remain legible in every appearance.
NSColor(srgbRed: 0.955, green: 0.958, blue: 0.965, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

if let arrow = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil) {
    let configured = arrow.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: 44, weight: .regular)
    ) ?? arrow
    configured.draw(
        in: NSRect(x: 312, y: 168, width: 56, height: 40),
        from: .zero,
        operation: .sourceOver,
        fraction: 0.5
    )
}

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
"Local on your Mac  ·  Powered by whisper.cpp".draw(
    in: NSRect(x: 40, y: 18, width: 600, height: 20),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor(srgbRed: 0.36, green: 0.37, blue: 0.40, alpha: 1),
        .paragraphStyle: paragraph
    ]
)

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render DMG background.\n", stderr)
    exit(1)
}
try png.write(to: outputURL, options: .atomic)
