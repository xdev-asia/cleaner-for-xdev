// Renders the app icon: swift scripts/make-icon.swift <out.png>
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let inset = size * 0.1
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
NSGradient(colors: [NSColor(red: 0.06, green: 0.10, blue: 0.22, alpha: 1), NSColor(red: 0.05, green: 0.42, blue: 0.55, alpha: 1)])!
    .draw(in: shape, angle: 60)
let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white, NSColor(red: 0.45, green: 0.95, blue: 0.85, alpha: 1)]))
if let symbol = NSImage(systemSymbolName: "internaldrive.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let s = symbol.size
    symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2 - size * 0.03, width: s.width, height: s.height))
}
if let sparkle = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size * 0.2, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(red: 0.45, green: 0.95, blue: 0.85, alpha: 1)]))) {
    let s = sparkle.size
    sparkle.draw(in: NSRect(x: size * 0.64, y: size * 0.6, width: s.width, height: s.height))
}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
