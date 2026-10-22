// Draws the ScreenShot app icon (1024×1024): the menu bar's camera.viewfinder motif, elaborated.
// Usage: swift Tools/make_icon.swift <output.png>
import AppKit

let S: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func gradient(_ colors: [CGColor], _ locs: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locs)!
}

// Apple's macOS grid: 824-pt body centered in 1024 with ~185-pt corners.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(bodyPath); ctx.setFillColor(rgb(0x1B1D2A)); ctx.fillPath()
ctx.restoreGState()

// Background: deep slate gradient with a warm glow behind the camera.
ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x2E3248), rgb(0x161826)]), start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
ctx.drawRadialGradient(gradient([rgb(0xFF5A1F, 0.42), rgb(0xFF0C01, 0.0)]), startCenter: CGPoint(x: 512, y: 470), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 470), endRadius: 430, options: [])
// Subtle top sheen.
ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)]), start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY + 120), options: [])
ctx.restoreGState()
// Hairline rim.
ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
ctx.setStrokeColor(rgb(0xFFFFFF, 0.12)); ctx.setLineWidth(3); ctx.strokePath()

// Viewfinder corner brackets in the brand red-orange gradient (Shottr's clrMain #FF0C01 family).
let frame = CGRect(x: 232, y: 232, width: 560, height: 560)
let arm: CGFloat = 150, thick: CGFloat = 44, r: CGFloat = 70
let brackets = CGMutablePath()
for (cx, cy, sx, sy) in [(frame.minX, frame.minY, 1.0, 1.0), (frame.maxX, frame.minY, -1.0, 1.0),
                         (frame.minX, frame.maxY, 1.0, -1.0), (frame.maxX, frame.maxY, -1.0, -1.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
    brackets.move(to: CGPoint(x: cx, y: cy + sy * arm))
    brackets.addLine(to: CGPoint(x: cx, y: cy + sy * r))
    brackets.addArc(tangent1End: CGPoint(x: cx, y: cy), tangent2End: CGPoint(x: cx + sx * r, y: cy), radius: r)
    brackets.addLine(to: CGPoint(x: cx + sx * arm, y: cy))
}
let bracketStroke = brackets.copy(strokingWithWidth: thick, lineCap: .round, lineJoin: .round, miterLimit: 10)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: rgb(0xFF2A00, 0.55))
ctx.addPath(bracketStroke); ctx.setFillColor(rgb(0xFF3B1A)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(bracketStroke); ctx.clip()
// The stroke reaches thick/2 past the frame, so the gradient must extend beyond its end points.
ctx.drawLinearGradient(gradient([rgb(0xFF9A3C), rgb(0xFF0C01)]), start: CGPoint(x: 0, y: frame.maxY), end: CGPoint(x: 0, y: frame.minY),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()

// Camera body.
let cam = CGRect(x: 322, y: 378, width: 380, height: 270)
let hump = CGRect(x: 432, y: 618, width: 160, height: 74)
let camPath = CGMutablePath()
camPath.addPath(CGPath(roundedRect: cam, cornerWidth: 58, cornerHeight: 58, transform: nil))
camPath.addPath(CGPath(roundedRect: hump, cornerWidth: 26, cornerHeight: 26, transform: nil))
let camShape = camPath.union(CGPath(rect: .zero, transform: nil))
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 30, color: rgb(0x000000, 0.45))
ctx.addPath(camShape); ctx.setFillColor(rgb(0xF4F5F8)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(camShape); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0xFFFFFF), rgb(0xD9DCE4)]), start: CGPoint(x: 0, y: hump.maxY), end: CGPoint(x: 0, y: cam.minY), options: [])
ctx.restoreGState()

// Shutter button and flash.
ctx.addPath(CGPath(roundedRect: CGRect(x: 368, y: 646, width: 54, height: 22), cornerWidth: 10, cornerHeight: 10, transform: nil))
ctx.setFillColor(rgb(0xFF3B1A)); ctx.fillPath()
ctx.addEllipse(in: CGRect(x: 628, y: 590, width: 30, height: 30)); ctx.setFillColor(rgb(0x9AA0AE)); ctx.fillPath()

// Lens: dark barrel, gradient glass, highlights.
let c = CGPoint(x: 512, y: 505)
func circle(_ radius: CGFloat) -> CGRect { CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius) }
ctx.addEllipse(in: circle(118)); ctx.setFillColor(rgb(0x262938)); ctx.fillPath()
ctx.addEllipse(in: circle(104)); ctx.setFillColor(rgb(0x3A3F55)); ctx.fillPath()
ctx.saveGState()
ctx.addEllipse(in: circle(86)); ctx.clip()
ctx.drawRadialGradient(gradient([rgb(0xFFB070), rgb(0xFF3B1A), rgb(0x7A0F2E), rgb(0x1A1030)], [0, 0.25, 0.7, 1]),
                       startCenter: CGPoint(x: c.x - 18, y: c.y + 22), startRadius: 0, endCenter: c, endRadius: 92, options: [])
ctx.restoreGState()
ctx.addEllipse(in: circle(34)); ctx.setFillColor(rgb(0x0E0A18, 0.85)); ctx.fillPath()
ctx.addEllipse(in: CGRect(x: c.x - 52, y: c.y + 20, width: 40, height: 28)); ctx.setFillColor(rgb(0xFFFFFF, 0.75)); ctx.fillPath()
ctx.addEllipse(in: CGRect(x: c.x + 30, y: c.y - 50, width: 16, height: 16)); ctx.setFillColor(rgb(0xFFFFFF, 0.35)); ctx.fillPath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote", out)
