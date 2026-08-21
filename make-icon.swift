import AppKit

let canvas = CGFloat(1024)
let margin = canvas * 0.098
let tileSide = canvas - margin * 2
let tileRect = NSRect(x: margin, y: margin, width: tileSide, height: tileSide)
let espresso = NSColor(srgbRed: 0.24, green: 0.15, blue: 0.08, alpha: 1)
let creamTop = NSColor(srgbRed: 1.00, green: 0.96, blue: 0.90, alpha: 1)
let creamBottom = NSColor(srgbRed: 0.90, green: 0.79, blue: 0.61, alpha: 1)

func cupPath(_ s: CGFloat) -> [NSBezierPath] {
    let u = s / 1024
    var paths: [NSBezierPath] = []

    let saucer = NSBezierPath(roundedRect: NSRect(x: 295 * u, y: 240 * u, width: 380 * u, height: 52 * u), xRadius: 26 * u, yRadius: 26 * u)
    paths.append(saucer)

    let handle = NSBezierPath(ovalIn: NSRect(x: 545 * u, y: 375 * u, width: 190 * u, height: 190 * u))
    handle.lineWidth = 56 * u
    paths.append(handle)

    let body = NSBezierPath(roundedRect: NSRect(x: 330 * u, y: 300 * u, width: 310 * u, height: 340 * u), xRadius: 70 * u, yRadius: 70 * u)
    paths.append(body)

    for x in [430.0, 540.0] {
        let steam = NSBezierPath()
        steam.move(to: NSPoint(x: x * u, y: 700 * u))
        steam.curve(to: NSPoint(x: x * u, y: 800 * u), controlPoint1: NSPoint(x: (x + 42) * u, y: 733 * u), controlPoint2: NSPoint(x: (x + 42) * u, y: 767 * u))
        steam.lineWidth = 26 * u
        steam.lineCapStyle = .round
        paths.append(steam)
    }
    return paths
}

func renderIcon(scaleTo size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!

    ctx.cgContext.setAllowsAntialiasing(true)
    ctx.cgContext.setShouldAntialias(true)

    let tile = NSBezierPath(roundedRect: tileRect, xRadius: tileSide * 0.225, yRadius: tileSide * 0.225)
    NSGradient(colors: [creamTop, creamBottom])!.draw(in: tile, angle: -90)

    for path in cupPath(canvas) {
        espresso.setStroke()
        espresso.setFill()
        if path.lineWidth > 0 {
            path.stroke()
        } else {
            path.fill()
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let specs: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (name, size) in specs {
    let rep = renderIcon(scaleTo: size)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print("wrote \(name)")
}
