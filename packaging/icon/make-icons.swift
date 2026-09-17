#!/usr/bin/env swift
// Renders the MeetingHop app icon and the menu-bar template image.
//
// Drawn in CoreGraphics rather than rasterised from SVG on purpose: the SVG
// rasterisers available without extra tooling drop gradients and strokes
// silently, and this project ships with no image dependencies. The shapes
// here are the source of truth. Mirrors agentmenu/packaging/icon/make-icons.swift.
//
//   swift packaging/icon/make-icons.swift            # -> dist/icon/
//
// Requires nothing but the Swift toolchain and AppKit.

import AppKit
import Foundation

// MARK: - Brand

/// Vertical gradient of the icon body, top to bottom. Same stops as
/// AgentMenu's — see docs/brand.md for why the palette is shared on purpose.
let bodyStops: [(CGFloat, NSColor)] = [
    (0.00, NSColor(srgbRed: 1.000, green: 0.494, blue: 0.714, alpha: 1)),   // #FF7EB6
    (0.42, NSColor(srgbRed: 0.839, green: 0.200, blue: 0.424, alpha: 1)),   // #D6336C
    (1.00, NSColor(srgbRed: 0.369, green: 0.063, blue: 0.180, alpha: 1)),   // #5E102E
]

/// A superellipse — Apple's icon silhouette is not a circular-cornered rect,
/// and at 1024px the difference is visible.
func squirclePath(in rect: CGRect, exponent: CGFloat = 5.0, steps: Int = 720) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    for step in 0...steps {
        let theta = 2 * CGFloat.pi * CGFloat(step) / CGFloat(steps)
        let ct = cos(theta), st = sin(theta)
        let x = cx + a * pow(abs(ct), 2 / exponent) * (ct < 0 ? -1 : 1)
        let y = cy + b * pow(abs(st), 2 / exponent) * (st < 0 ? -1 : 1)
        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

/// The mark, drawn once. `p` maps a point on the 18 pt template grid — the
/// grid the glyph is authored on — into the destination context; `len` maps a
/// length. The app icon and the menu-bar image are the same drawing at two
/// sizes, which is the only thing that keeps them from drifting apart.
///
/// A video camera with a straight arrow driving into it. Three rules hold it
/// together, each one the fix for something that failed:
///
///   - The arrow is knocked OUT of the body rather than drawn on the gradient.
///     The body carries the mass and the arrow only has to carry contrast, so
///     it can stay this fine and still read when the icon is 16 px.
///   - The gap between the body and the lens wedge is load-bearing. Closed up,
///     the two fuse into a single hexagon and the camera is gone.
///   - The arrow is half the body's height, not four fifths. At four fifths it
///     swamped the camera it was supposed to be entering.
///
/// The arrow is centred in the body by measuring the rendered bitmap, not by
/// eye: it sits 113/112 px horizontally and 98/98 px vertically at 1024.
func drawCamera(in context: CGContext, color: NSColor,
                p: (CGFloat, CGFloat) -> CGPoint, len: (CGFloat) -> CGFloat) {
    context.saveGState()
    context.setFillColor(color.cgColor)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    // Everything inside the layer composites as one shape, so the knockout
    // below clears the arrow out of the glyph rather than out of the icon.
    context.beginTransparencyLayer(auxiliaryInfo: nil)

    // The screen.
    let topLeft = p(1.4, 4.9)
    let body = CGRect(x: topLeft.x, y: topLeft.y - len(8.4), width: len(10.6), height: len(8.4))
    context.addPath(CGPath(roundedRect: body, cornerWidth: len(2.1), cornerHeight: len(2.1), transform: nil))
    context.fillPath()

    // The lens, and the gap that keeps it a lens.
    context.beginPath()
    context.move(to: p(13.2, 7.3))
    context.addLine(to: p(16.7, 5.3))
    context.addLine(to: p(16.7, 12.9))
    context.addLine(to: p(13.2, 10.9))
    context.closePath()
    context.fillPath()

    // The arrow, cleared out of what is already drawn.
    context.setBlendMode(.destinationOut)
    context.setStrokeColor(NSColor.black.cgColor)
    context.setLineWidth(len(1.2))
    context.beginPath()
    context.move(to: p(4.46, 9.1))
    context.addLine(to: p(8.86, 9.1))
    context.strokePath()
    context.beginPath()
    context.move(to: p(7.41, 7.65))
    context.addLine(to: p(8.96, 9.1))
    context.addLine(to: p(7.41, 10.55))
    context.strokePath()
    context.setBlendMode(.normal)

    context.endTransparencyLayer()
    context.restoreGState()
}

/// The glyph on the app icon's 1024 grid: the template drawing, 700 units
/// wide, centred on the body. `side` is the size of the square it is drawn
/// into, origin at its bottom-left, in CoreGraphics' y-up space.
func drawGlyph(in context: CGContext, side: CGFloat, origin: CGPoint, color: NSColor) {
    let s = side / 1024.0
    context.saveGState()
    context.translateBy(x: origin.x, y: origin.y)

    // Template bbox is x 1.4...16.7, y 4.9...13.3 — centre (9.05, 9.1). It
    // lands 700 units wide, centred at (512, 508): four units above the
    // geometric centre, which is the usual optical lift.
    let unit: CGFloat = 700.0 / 15.3
    let ox = 512 - 9.05 * unit, oy = 508 - 9.1 * unit
    // Coordinates are quoted y-down on the design grid and flipped here.
    drawCamera(
        in: context, color: color,
        p: { x, y in CGPoint(x: (ox + unit * x) * s, y: (1024 - (oy + unit * y)) * s) },
        len: { v in unit * v * s }
    )

    context.restoreGState()
}

// MARK: - Renderers

func renderAppIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("could not allocate a \(pixels)px bitmap") }

    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext

    // macOS icon grid: the artwork occupies 832 of 1024, centred.
    let inset = size * (96.0 / 1024.0)
    let body = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = squirclePath(in: body)

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let colors = bodyStops.map { $0.1.cgColor } as CFArray
    let locations = bodyStops.map { $0.0 }
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: body.midX, y: body.maxY),
            end: CGPoint(x: body.midX, y: body.minY),
            options: []
        )
    }
    // A single soft highlight along the top edge — depth without a plastic sheen.
    if let sheen = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(white: 1, alpha: 0.30).cgColor,
            NSColor(white: 1, alpha: 0.0).cgColor,
        ] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            sheen,
            start: CGPoint(x: body.midX, y: body.maxY),
            end: CGPoint(x: body.midX, y: body.midY + body.height * 0.06),
            options: []
        )
    }
    context.restoreGState()

    // Hairline, so the icon keeps an edge on a white background.
    context.saveGState()
    context.addPath(shape)
    context.setStrokeColor(NSColor(srgbRed: 0.22, green: 0.02, blue: 0.09, alpha: 0.28).cgColor)
    context.setLineWidth(max(1, size * (8.0 / 1024.0)))
    context.strokePath()
    context.restoreGState()

    drawGlyph(in: context, side: size, origin: .zero, color: NSColor(white: 1, alpha: 0.96))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// The menu-bar image is a template: one colour plus alpha, drawn at the point
/// size AppKit asks for. macOS tints it for light, dark and the active state,
/// so any colour here would be thrown away. This is the same drawing as the
/// app icon, at its native size: the mark is authored on this 18 pt grid and
/// scaled UP for the icon, rather than drawn large and reduced.
func renderMenuBarTemplate(points: CGFloat, scale: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(points * scale)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("could not allocate a \(pixels)px bitmap") }
    rep.size = NSSize(width: points, height: points)

    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = graphics
    // The rep's size is in points while its backing store is in pixels, so the
    // graphics context already scales; scaling again here would draw at 4x.
    let context = graphics.cgContext
    let s = points / 18.0

    // This is the grid the mark is authored on, so the numbers go in as they
    // are. The glyph's own bbox centre is (9.05, 9.1) against a box centre of
    // (9, 9); the nudge puts it dead centre in the menu-bar item.
    let dx: CGFloat = -0.05, dy: CGFloat = -0.1
    drawCamera(
        in: context, color: .black,
        p: { x, y in CGPoint(x: (x + dx) * s, y: (18 - (y + dy)) * s) },
        len: { v in v * s }
    )

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to url: URL) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(url.lastPathComponent)")
    }
    try! data.write(to: url)
}

// MARK: - Main

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let out = root.appendingPathComponent("dist/icon")
let iconset = out.appendingPathComponent("MeetingHop.iconset")
let menubar = out.appendingPathComponent("menubar")
for dir in [out, iconset, menubar] {
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
}

// The names iconutil expects.
let iconSizes: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in iconSizes {
    write(renderAppIcon(size: size), to: iconset.appendingPathComponent("\(name).png"))
}
write(renderAppIcon(size: 1024), to: out.appendingPathComponent("MeetingHop-1024.png"))

for (suffix, scale) in [("", CGFloat(1)), ("@2x", 2), ("@3x", 3)] {
    write(renderMenuBarTemplate(points: 18, scale: scale),
          to: menubar.appendingPathComponent("MenuBarIconTemplate\(suffix).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", out.appendingPathComponent("MeetingHop.icns").path, iconset.path]
try! iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

print("wrote \(out.path): MeetingHop.icns, MeetingHop-1024.png, menubar/MenuBarIconTemplate{,@2x,@3x}.png")
