import AppKit
import CoreImage

/// Shottr's backdrop panel: a background around the screenshot with aspect presets, padding, shadow, inset,
/// corner radii and several fills. Sizes are fractions of the screenshot's longer side, so they survive resizing.
struct Backdrop: Codable, Equatable {
    enum Fill: String, Codable, CaseIterable {
        case solid, blend, vertical, diagonal, radial, mesh, blurredImage

        var title: String {
            switch self {
            case .solid: "Solid Color"
            case .blend: "Color Blend"
            case .vertical: "Vertical Gradient"
            case .diagonal: "Diagonal Gradient"
            case .radial: "Radial Gradient"
            case .mesh: "Mesh Gradient"
            case .blurredImage: "Blurred Screenshot"
            }
        }
    }

    enum Aspect: String, Codable, CaseIterable {
        case auto, square, r4x3, r3x2, r16x9, twitter, facebook, youtube, linkedin, pinterest

        var title: String {
            switch self {
            case .auto: "Auto"
            case .square: "1:1"
            case .r4x3: "4:3"
            case .r3x2: "3:2"
            case .r16x9: "16:9"
            case .twitter: "Twitter / X (16:9)"
            case .facebook: "Facebook (1.91:1)"
            case .youtube: "YouTube (16:9)"
            case .linkedin: "LinkedIn (1.91:1)"
            case .pinterest: "Pinterest (2:3)"
            }
        }

        /// Width ÷ height, nil for Auto (the padding decides the size).
        var ratio: CGFloat? {
            switch self {
            case .auto: nil
            case .square: 1
            case .r4x3: 4 / 3
            case .r3x2: 3 / 2
            case .r16x9, .twitter, .youtube: 16 / 9
            case .facebook: 1200 / 628
            case .linkedin: 1200 / 627
            case .pinterest: 2 / 3
            }
        }
    }

    /// Named color pairs offered as swatches; the first six are the backdrops of earlier versions.
    struct Preset {
        let title: String
        let colors: [String]
    }
    static let presets: [Preset] = [
        Preset(title: "Ocean", colors: ["#4FACFE", "#00F2FE"]),
        Preset(title: "Sunset", colors: ["#FA709A", "#FEE140"]),
        Preset(title: "Mint", colors: ["#43E97B", "#38F9D7"]),
        Preset(title: "Grape", colors: ["#7F00FF", "#E100FF"]),
        Preset(title: "Graphite", colors: ["#434343", "#000000"]),
        Preset(title: "Paper", colors: ["#FDFBFB", "#EBEDEE"]),
        Preset(title: "Peach", colors: ["#FFDDE1", "#EE9CA7"]),
        Preset(title: "Night", colors: ["#0F2027", "#2C5364"]),
        Preset(title: "Lagoon", colors: ["#13547A", "#80D0C7"]),
        Preset(title: "Flamingo", colors: ["#F857A6", "#FF5858"]),
    ]

    var isOn = false
    var fill: Fill = .diagonal
    var colors: [String] = ["#4FACFE", "#00F2FE"]
    var aspect: Aspect = .auto
    var padding: CGFloat = 0.07
    /// Shadow opacity, 0…1.
    var shadow: CGFloat = 0.45
    /// A translucent frame around the screenshot.
    var inset: CGFloat = 0
    /// Rounds the corners of the whole picture (they become transparent).
    var outerRadius: CGFloat = 0
    /// Rounds the corners of the screenshot.
    var innerRadius: CGFloat = 0.012
    /// Where the screenshot sits in the free space: -1…1 on each axis, 0 is centered.
    var offset: CGPoint = .zero

    static let none = Backdrop()

    init() {}

    var nsColors: [NSColor] {
        let c = colors.compactMap { NSColor(rgbaHex: $0) }
        return c.isEmpty ? [.white] : c
    }

    // MARK: Defaults

    /// What K turns on: the backdrop last used or set as default, so a favorite look is one key away.
    static var lastUsed: Backdrop {
        get {
            guard let d = UserDefaults.standard.data(forKey: "lastBackdrop"), var b = try? JSONDecoder().decode(Backdrop.self, from: d)
            else { var b = Backdrop(); b.isOn = true; return b }
            b.isOn = true
            b.offset = .zero
            return b
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "lastBackdrop") }
    }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case isOn, fill, colors, aspect, padding, shadow, inset, outerRadius, innerRadius, offset
    }

    init(from decoder: Decoder) throws {
        // Files saved before the panel existed store the backdrop as a preset number (0 = none).
        if let legacy = try? decoder.singleValueContainer().decode(Int.self) {
            if legacy > 0, legacy <= Self.presets.count {
                isOn = true
                colors = Self.presets[legacy - 1].colors
            }
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isOn = try c.decodeIfPresent(Bool.self, forKey: .isOn) ?? false
        fill = try c.decodeIfPresent(Fill.self, forKey: .fill) ?? .diagonal
        colors = try c.decodeIfPresent([String].self, forKey: .colors) ?? colors
        aspect = try c.decodeIfPresent(Aspect.self, forKey: .aspect) ?? .auto
        padding = try c.decodeIfPresent(CGFloat.self, forKey: .padding) ?? padding
        shadow = try c.decodeIfPresent(CGFloat.self, forKey: .shadow) ?? shadow
        inset = try c.decodeIfPresent(CGFloat.self, forKey: .inset) ?? 0
        outerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .outerRadius) ?? 0
        innerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .innerRadius) ?? innerRadius
        offset = try c.decodeIfPresent(CGPoint.self, forKey: .offset) ?? .zero
    }
}

/// Where everything goes on the canvas, in canvas pixels.
struct BackdropLayout {
    let canvas: CGSize
    /// The screenshot's top-left corner.
    let imageOrigin: CGPoint
    /// Everything shown (the screenshot and objects past its edges) plus the inset frame.
    let content: CGRect
    /// Width of the inset frame, in canvas pixels.
    let inset: CGFloat
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let shadowBlur: CGFloat
    /// How far `offset` can move the content on each axis (half of the free space).
    let travel: CGSize

    /// `contentRect` is what must be visible, in image coordinates: the image, grown to include objects drawn past its
    /// edges (so it can start at negative coordinates).
    init(_ b: Backdrop, imageSize: CGSize, contentRect: CGRect? = nil) {
        let area = contentRect ?? CGRect(origin: .zero, size: imageSize)
        let s = area.size
        guard b.isOn else {
            canvas = s
            imageOrigin = CGPoint(x: -area.minX, y: -area.minY)
            content = CGRect(origin: .zero, size: s)
            inset = 0
            innerRadius = 0
            outerRadius = 0
            shadowBlur = 0
            travel = .zero
            return
        }
        let long = max(s.width, s.height)
        let pad = (b.padding * long).rounded()
        let ins = (b.inset * long).rounded()
        let contentSize = CGSize(width: s.width + 2 * ins, height: s.height + 2 * ins)
        var size = CGSize(width: contentSize.width + 2 * pad, height: contentSize.height + 2 * pad)
        if let r = b.aspect.ratio {
            if size.width / size.height < r { size.width = (size.height * r).rounded() } else { size.height = (size.width / r).rounded() }
        }
        canvas = size
        travel = CGSize(width: (size.width - contentSize.width) / 2, height: (size.height - contentSize.height) / 2)
        let o = CGPoint(x: (travel.width * (1 + max(-1, min(1, b.offset.x)))).rounded(),
                        y: (travel.height * (1 + max(-1, min(1, b.offset.y)))).rounded())
        content = CGRect(origin: o, size: contentSize)
        inset = ins
        imageOrigin = CGPoint(x: o.x + ins - area.minX, y: o.y + ins - area.minY)
        innerRadius = b.innerRadius * long
        outerRadius = b.outerRadius * min(size.width, size.height)
        shadowBlur = max(pad, long * 0.04) * 0.5
    }
}

enum BackdropPainter {
    /// Fills the canvas (flipped context, canvas pixels). `image` is the screenshot for the blurred fill.
    static func paintFill(_ b: Backdrop, size: CGSize, image: CGImage, blurred: () -> CGImage?, in ctx: CGContext) {
        let rect = CGRect(origin: .zero, size: size)
        let cols = b.nsColors
        let c0 = cols[0], c1 = cols.count > 1 ? cols[1] : cols[0]
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        func gradient(_ c: [NSColor]) -> CGGradient? {
            CGGradient(colorsSpace: space, colors: c.map { $0.usingColorSpace(.sRGB)?.cgColor ?? $0.cgColor } as CFArray, locations: nil)
        }
        switch b.fill {
        case .solid:
            ctx.setFillColor(c0.cgColor)
            ctx.fill(rect)
        case .blend:
            // A soft three-stop mix through the midpoint color.
            let mid = c0.blended(withFraction: 0.5, of: c1) ?? c0
            if let g = gradient([c0, mid, c1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: size.height * 0.5), end: CGPoint(x: size.width, y: size.height * 0.5), options: [])
            }
        case .vertical:
            if let g = gradient([c0, c1]) { ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: []) }
        case .diagonal:
            if let g = gradient([c0, c1]) { ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: []) }
        case .radial:
            if let g = gradient([c0, c1]) {
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: hypot(size.width, size.height) / 2,
                                       options: [.drawsAfterEndLocation])
            }
        case .mesh:
            // Soft color blobs over a base, like a mesh gradient: each corner pulls toward its own color.
            ctx.setFillColor((c0.blended(withFraction: 0.5, of: c1) ?? c0).cgColor)
            ctx.fill(rect)
            let warm = c0.blended(withFraction: 0.35, of: .white) ?? c0
            let deep = c1.blended(withFraction: 0.25, of: .black) ?? c1
            let blobs: [(CGPoint, NSColor)] = [(CGPoint(x: 0, y: 0), c0), (CGPoint(x: size.width, y: size.height), c1),
                                               (CGPoint(x: size.width, y: 0), warm), (CGPoint(x: 0, y: size.height), deep)]
            let r = max(size.width, size.height) * 0.85
            for (p, c) in blobs {
                if let g = gradient([c, c.withAlphaComponent(0)]) {
                    ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
                }
            }
        case .blurredImage:
            if let img = blurred() {
                // Aspect-fill the canvas.
                let k = max(size.width / CGFloat(img.width), size.height / CGFloat(img.height))
                let w = CGFloat(img.width) * k, h = CGFloat(img.height) * k
                ctx.drawFlipped(img, in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
                ctx.setFillColor(NSColor.black.withAlphaComponent(0.12).cgColor)
                ctx.fill(rect)
            } else {
                ctx.setFillColor(c0.cgColor)
                ctx.fill(rect)
            }
        }
    }

    /// The screenshot heavily blurred, small enough to be cheap; edges are clamped so they don't fade to transparent.
    static func blurred(_ image: CGImage) -> CGImage? {
        let long = CGFloat(max(image.width, image.height))
        let k = min(1, 480 / long)
        let ci = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: k, y: k))
        let extent = ci.extent
        guard let f = CIFilter(name: "CIGaussianBlur") else { return nil }
        f.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
        f.setValue(max(8, extent.width * 0.04), forKey: kCIInputRadiusKey)
        guard let out = f.outputImage?.cropped(to: extent) else { return nil }
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(out, from: extent)
    }
}
