// Draws the KoeType app icon and writes AppIcon.iconset next to this script.
// Usage: swift Support/icon/make-icon.swift && iconutil -c icns Support/icon/AppIcon.iconset -o Support/AppIcon.icns
import AppKit

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    let unit = size / 1024

    // macOS icon grid: an 824 pt rounded square centred on a 1024 pt canvas.
    let body = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let shape = CGPath(roundedRect: body, cornerWidth: 185 * unit, cornerHeight: 185 * unit, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 24 * unit,
                      color: NSColor.black.withAlphaComponent(0.3).cgColor)
    context.addPath(shape)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let colors = [NSColor(red: 0.10, green: 0.13, blue: 0.24, alpha: 1).cgColor,
                  NSColor(red: 0.05, green: 0.06, blue: 0.12, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    // Soft glow behind the waveform.
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [NSColor(red: 0.35, green: 0.75, blue: 1, alpha: 0.28).cgColor,
                                   NSColor(red: 0.35, green: 0.75, blue: 1, alpha: 0).cgColor] as CFArray,
                          locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 512 * unit, y: 512 * unit), startRadius: 0,
                               endCenter: CGPoint(x: 512 * unit, y: 512 * unit), endRadius: 420 * unit, options: [])
    context.restoreGState()

    // The waveform from the recording indicator: the voice, as bars.
    let heights: [CGFloat] = [0.22, 0.42, 0.70, 1.0, 0.58, 0.86, 0.48, 0.28, 0.16]
    let barWidth = 46 * unit, gap = 30 * unit
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = (size - total) / 2
    for height in heights {
        let barHeight = 440 * unit * height
        let bar = CGRect(x: x, y: 512 * unit - barHeight / 2, width: barWidth, height: barHeight)
        let path = CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
        context.saveGState()
        context.addPath(path)
        context.clip()
        let barColors = [NSColor.white.cgColor, NSColor(red: 0.55, green: 0.86, blue: 1, alpha: 1).cgColor] as CFArray
        let barGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: barColors, locations: [0, 1])!
        context.drawLinearGradient(barGradient, start: CGPoint(x: 0, y: bar.maxY), end: CGPoint(x: 0, y: bar.minY), options: [])
        context.restoreGState()
        x += barWidth + gap
    }

    // Thin highlight along the top edge.
    context.addPath(shape)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
    context.setLineWidth(4 * unit)
    context.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    let data = render(size: CGFloat(points * scale)).representation(using: .png, properties: [:])!
    try data.write(to: folder.appendingPathComponent(name))
}
print("wrote", folder.path)
