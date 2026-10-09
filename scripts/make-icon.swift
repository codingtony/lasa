// Renders the app icon to Packaging/AppIcon.icns: a page whose current line is highlighted,
// speaking (sound waves), on a Swedish-blue macOS-style rounded square.
// Usage: swift scripts/make-icon.swift   (writes Packaging/AppIcon.icns and build/AppIcon.png)
import AppKit

let blueTop = CGColor(srgbRed: 0.12, green: 0.50, blue: 0.80, alpha: 1)
let blueBottom = CGColor(srgbRed: 0.00, green: 0.30, blue: 0.58, alpha: 1)
let yellow = CGColor(srgbRed: 1.00, green: 0.80, blue: 0.01, alpha: 1)
let lineGray = CGColor(srgbRed: 0.78, green: 0.82, blue: 0.87, alpha: 1)
let ink = CGColor(srgbRed: 0.16, green: 0.20, blue: 0.27, alpha: 1)

/// Draws the icon on a 1024-point canvas (origin bottom-left), scaled to `size` pixels.
func render(size: Int) -> NSBitmapImageRep {
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    // Body on Apple's macOS grid: 824 pt square, 100 pt margin, continuous-looking corners.
    let body = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(body)
    ctx.setFillColor(blueBottom)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: nil, colors: [blueTop, blueBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Page with a folded top-right corner.
    let page = CGRect(x: 205, y: 215, width: 400, height: 594)
    let fold: CGFloat = 92
    let pagePath = CGMutablePath()
    pagePath.move(to: CGPoint(x: page.minX, y: page.minY))
    pagePath.addLine(to: CGPoint(x: page.maxX, y: page.minY))
    pagePath.addLine(to: CGPoint(x: page.maxX, y: page.maxY - fold))
    pagePath.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY))
    pagePath.addLine(to: CGPoint(x: page.minX, y: page.maxY))
    pagePath.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: CGColor(gray: 0, alpha: 0.30))
    ctx.addPath(pagePath)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    let foldPath = CGMutablePath()
    foldPath.move(to: CGPoint(x: page.maxX - fold, y: page.maxY))
    foldPath.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY - fold))
    foldPath.addLine(to: CGPoint(x: page.maxX, y: page.maxY - fold))
    foldPath.closeSubpath()
    ctx.addPath(foldPath)
    ctx.setFillColor(lineGray)
    ctx.fillPath()

    // Text lines; the fourth is the sentence being read.
    let left = page.minX + 48
    let widths: [CGFloat] = [210, 300, 270, 290, 300, 240, 300, 180]
    let highlighted = 3
    for (i, width) in widths.enumerated() {
        let y = page.maxY - 150 - CGFloat(i) * 52
        if i == highlighted {
            let mark = CGRect(x: left - 16, y: y - 15, width: width + 32, height: 52)
            ctx.addPath(CGPath(roundedRect: mark, cornerWidth: 12, cornerHeight: 12, transform: nil))
            ctx.setFillColor(yellow)
            ctx.fillPath()
        }
        ctx.addPath(CGPath(roundedRect: CGRect(x: left, y: y, width: width, height: 22), cornerWidth: 11, cornerHeight: 11, transform: nil))
        ctx.setFillColor(i == highlighted ? ink : lineGray)
        ctx.fillPath()
    }

    // Sound waves leaving the highlighted line.
    let center = CGPoint(x: page.maxX + 18, y: page.maxY - 150 - CGFloat(highlighted) * 52 + 11)
    ctx.setStrokeColor(yellow)
    ctx.setLineCap(.round)
    for (i, radius) in [CGFloat(78), 150, 222].enumerated() {
        ctx.setLineWidth(38 - CGFloat(i) * 4)
        ctx.addArc(center: center, radius: radius, startAngle: -.pi / 4, endAngle: .pi / 4, clockwise: false)
        ctx.strokePath()
    }
    ctx.restoreGState()

    return NSBitmapImageRep(cgImage: ctx.makeImage()!)
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let buildDir = root.appendingPathComponent("build")
let iconset = buildDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try writePNG(render(size: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try writePNG(render(size: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try writePNG(render(size: 1024), to: buildDir.appendingPathComponent("AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Packaging/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote Packaging/AppIcon.icns and build/AppIcon.png")
