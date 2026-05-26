#!/usr/bin/env swift

// Renders the Skoga app icon to PNGs at every macOS-required size and (re)writes
// Skoga/Assets.xcassets/AppIcon.appiconset. Run with: swift tools/generate-app-icon.swift
//
// The icon source of truth lives in this file — the two pine paths mirror
// Skoga/Components/SkogaGlyph.swift so the icon and the in-app glyph stay aligned.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit

// MARK: - OKLCH → sRGB (mirrors Skoga/Design/Color+Oklch.swift)

func oklchSRGB(_ l: Double, _ c: Double, _ h: Double) -> (CGFloat, CGFloat, CGFloat) {
    let hRad = h * .pi / 180.0
    let a = c * cos(hRad)
    let b = c * sin(hRad)
    let l_ = l + 0.3963377774 * a + 0.2158037573 * b
    let m_ = l - 0.1055613458 * a - 0.0638541728 * b
    let s_ = l - 0.0894841775 * a - 1.2914855480 * b
    let lc = l_ * l_ * l_, mc = m_ * m_ * m_, sc = s_ * s_ * s_
    let rLin =  4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc
    let gLin = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc
    let bLin = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc
    func enc(_ x: Double) -> Double {
        let v = max(0.0, min(1.0, x))
        return v >= 0.0031308 ? 1.055 * pow(v, 1.0 / 2.4) - 0.055 : 12.92 * v
    }
    return (CGFloat(enc(rLin)), CGFloat(enc(gLin)), CGFloat(enc(bLin)))
}

func color(_ l: Double, _ c: Double, _ h: Double, _ a: CGFloat = 1) -> CGColor {
    let (r, g, b) = oklchSRGB(l, c, h)
    return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// Palette tokens taken from Skoga/Design/Theme.swift (light).
let paper      = color(0.955, 0.018, 80)
let paper2     = color(0.928, 0.026, 78)
let rule       = color(0.62,  0.025, 70, 0.18)
let forest     = color(0.46,  0.085, 145)
let moss       = color(0.58,  0.050, 130)
let shadowInk  = color(0.20,  0.012, 60, 0.10)

// MARK: - Icon

func drawIcon(pixels: Int) -> CGImage? {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil,
        width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Work in a 1024-unit logical canvas regardless of pixel size.
    let scale = CGFloat(pixels) / 1024.0
    ctx.scaleBy(x: scale, y: scale)

    // macOS HIG: 824×824 squircle centered in 1024×1024 (100px inset, 185 corner).
    let canvas: CGFloat = 1024
    let inset: CGFloat  = 100
    let cornerR: CGFloat = 185
    let tileRect = CGRect(x: inset, y: inset, width: canvas - 2*inset, height: canvas - 2*inset)
    let tilePath = CGPath(roundedRect: tileRect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)

    // Drop shadow under the tile, hinting at depth on the Dock.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: shadowInk)
    ctx.addPath(tilePath)
    ctx.setFillColor(paper)
    ctx.fillPath()
    ctx.restoreGState()

    // Parchment fill — soft top-to-bottom gradient (CG y-axis is up, so paper at top = maxY).
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: cs,
        colors: [paper, paper2] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: tileRect.midX, y: tileRect.maxY),
        end:   CGPoint(x: tileRect.midX, y: tileRect.minY),
        options: []
    )
    ctx.restoreGState()

    // Hairline border to give the squircle a printed-card edge.
    ctx.addPath(tilePath)
    ctx.setStrokeColor(rule)
    ctx.setLineWidth(3)
    ctx.strokePath()

    // Trees occupy a centered square inside the tile. Glyph code from
    // SkogaGlyph uses a 24-unit grid with top-left origin (SwiftUI), so we flip Y.
    let treesSide: CGFloat = 760
    let originX = (canvas - treesSide) / 2
    let originY = (canvas - treesSide) / 2
    let s = treesSide / 24.0

    ctx.saveGState()
    ctx.translateBy(x: originX, y: originY + treesSide)
    ctx.scaleBy(x: s, y: -s)

    // Back tree (sage)
    drawTree(ctx, cx: 8.6,  top: 4.8, baseY: 19.2, halfWidth: 4.6, fill: moss,
             trunkTop: 19.2, trunkBottom: 21.0, trunkWidth: 1.2)
    // Front tree (deep forest) — overlaps the back, anchors the icon.
    drawTree(ctx, cx: 14.4, top: 2.4, baseY: 20.0, halfWidth: 6.2, fill: forest,
             trunkTop: 20.0, trunkBottom: 22.4, trunkWidth: 1.4)

    ctx.restoreGState()

    return ctx.makeImage()
}

func drawTree(
    _ ctx: CGContext,
    cx: CGFloat, top: CGFloat, baseY: CGFloat, halfWidth hw: CGFloat,
    fill: CGColor,
    trunkTop: CGFloat, trunkBottom: CGFloat, trunkWidth: CGFloat
) {
    let h = baseY - top
    let row1 = top + h * 0.32
    let row1In = top + h * 0.30
    let row2 = top + h * 0.62
    let row2In = top + h * 0.60
    let inset: CGFloat = hw * 0.45
    let inset2: CGFloat = hw * 0.20

    let foliage = CGMutablePath()
    foliage.move(to:    CGPoint(x: cx,                          y: top))
    foliage.addLine(to: CGPoint(x: cx + hw * 0.55,              y: row1))
    foliage.addLine(to: CGPoint(x: cx + hw * 0.55 - inset,      y: row1In))
    foliage.addLine(to: CGPoint(x: cx + hw * 0.82,              y: row2))
    foliage.addLine(to: CGPoint(x: cx + hw * 0.82 - inset2,     y: row2In))
    foliage.addLine(to: CGPoint(x: cx + hw,                     y: baseY))
    foliage.addLine(to: CGPoint(x: cx - hw,                     y: baseY))
    foliage.addLine(to: CGPoint(x: cx - hw * 0.82 + inset2,     y: row2In))
    foliage.addLine(to: CGPoint(x: cx - hw * 0.82,              y: row2))
    foliage.addLine(to: CGPoint(x: cx - hw * 0.55 + inset,      y: row1In))
    foliage.addLine(to: CGPoint(x: cx - hw * 0.55,              y: row1))
    foliage.closeSubpath()

    ctx.addPath(foliage)
    ctx.setFillColor(fill)
    ctx.fillPath()

    ctx.setStrokeColor(fill)
    ctx.setLineCap(.round)
    ctx.setLineWidth(trunkWidth)
    ctx.move(to:    CGPoint(x: cx, y: trunkTop))
    ctx.addLine(to: CGPoint(x: cx, y: trunkBottom))
    ctx.strokePath()
}

// MARK: - PNG output

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not create destination"]) }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "could not finalize PNG"])
    }
}

// MARK: - main

do {
    let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
    let catalog  = repoRoot.appendingPathComponent("Skoga/Assets.xcassets", isDirectory: true)
    let setDir   = catalog.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
    let fm = FileManager.default
    try fm.createDirectory(at: setDir, withIntermediateDirectories: true)

    // macOS asset catalog needs 16/32/64/128/256/512/1024 unique pixel sizes.
    let sizes = [16, 32, 64, 128, 256, 512, 1024]
    for px in sizes {
        guard let image = drawIcon(pixels: px) else {
            FileHandle.standardError.write(Data("failed to render \(px)\n".utf8))
            exit(1)
        }
        let url = setDir.appendingPathComponent("AppIcon-\(px).png")
        try writePNG(image, to: url)
        print("wrote \(url.lastPathComponent)")
    }

    let appIconContents = """
    {
      "images" : [
        { "size" : "16x16",   "idiom" : "mac", "filename" : "AppIcon-16.png",   "scale" : "1x" },
        { "size" : "16x16",   "idiom" : "mac", "filename" : "AppIcon-32.png",   "scale" : "2x" },
        { "size" : "32x32",   "idiom" : "mac", "filename" : "AppIcon-32.png",   "scale" : "1x" },
        { "size" : "32x32",   "idiom" : "mac", "filename" : "AppIcon-64.png",   "scale" : "2x" },
        { "size" : "128x128", "idiom" : "mac", "filename" : "AppIcon-128.png",  "scale" : "1x" },
        { "size" : "128x128", "idiom" : "mac", "filename" : "AppIcon-256.png",  "scale" : "2x" },
        { "size" : "256x256", "idiom" : "mac", "filename" : "AppIcon-256.png",  "scale" : "1x" },
        { "size" : "256x256", "idiom" : "mac", "filename" : "AppIcon-512.png",  "scale" : "2x" },
        { "size" : "512x512", "idiom" : "mac", "filename" : "AppIcon-512.png",  "scale" : "1x" },
        { "size" : "512x512", "idiom" : "mac", "filename" : "AppIcon-1024.png", "scale" : "2x" }
      ],
      "info" : { "version" : 1, "author" : "xcode" }
    }

    """
    try appIconContents.write(
        to: setDir.appendingPathComponent("Contents.json"),
        atomically: true, encoding: .utf8
    )
    print("wrote AppIcon.appiconset/Contents.json")

    let catalogContents = """
    {
      "info" : { "version" : 1, "author" : "xcode" }
    }

    """
    try catalogContents.write(
        to: catalog.appendingPathComponent("Contents.json"),
        atomically: true, encoding: .utf8
    )
    print("wrote Assets.xcassets/Contents.json")
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
