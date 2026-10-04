// Run from the repository root: swift tool/generate_icons.swift
// Vector-drawn layered mark; no image or font dependencies.
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func icon(size: Int, destination: URL) throws {
    let representation = NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    NSColor(red: 23 / 255, green: 107 / 255, blue: 96 / 255, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
    func line(_ points: [NSPoint], closed: Bool, color: NSColor) {
        let path = NSBezierPath()
        path.lineWidth = 58
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.move(to: points[0])
        for point in points.dropFirst() { path.line(to: point) }
        if closed { path.close() }
        color.setStroke()
        path.stroke()
    }
    line([NSPoint(x: 284, y: 460), NSPoint(x: 512, y: 326), NSPoint(x: 740, y: 460)],
         closed: false, color: NSColor(red: 190 / 255, green: 222 / 255, blue: 205 / 255, alpha: 1))
    line([NSPoint(x: 284, y: 590), NSPoint(x: 512, y: 724),
          NSPoint(x: 740, y: 590), NSPoint(x: 512, y: 456)],
         closed: true, color: .white)
    NSGraphicsContext.restoreGraphicsState()
    let png = representation.representation(using: .png, properties: [:])!
    try png.write(to: destination)
}

let appIcons = root.appendingPathComponent("ios/Runner/Assets.xcassets/AppIcon.appiconset")
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: appIcons.appendingPathComponent("Contents.json"))) as! [String: Any]
for entry in manifest["images"] as! [[String: String]] {
    let base = Double(entry["size"]!.components(separatedBy: "x")[0])!
    let scale = Double(entry["scale"]!.replacingOccurrences(of: "x", with: ""))!
    try icon(size: Int(base * scale), destination: appIcons.appendingPathComponent(entry["filename"]!))
}
for (density, size) in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)] {
    try icon(size: size, destination: root.appendingPathComponent("android/app/src/main/res/mipmap-\(density)/ic_launcher.png"))
}
print("Generated Android and iOS launcher icons.")
