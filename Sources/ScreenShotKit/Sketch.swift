import AppKit

/// Hand-drawn look for arrows, lines and shapes: every stroke is drawn twice along slightly wobbly curves, like a pen
/// going over a line again. The wobble is seeded by the annotation's id, so it stays the same on every redraw.
enum Sketch {
    struct RNG {
        private var state: UInt64

        init(_ id: UUID) {
            var h: UInt64 = 0xCBF2_9CE4_8422_2325
            withUnsafeBytes(of: id.uuid) { for b in $0 { h = (h ^ UInt64(b)) &* 0x100_0000_01B3 } }
            state = h | 1
        }

        /// -1…1
        mutating func next() -> CGFloat {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return CGFloat(state % 20001) / 10000 - 1
        }
    }

    /// How far strokes wander from the true line, growing with the pen width and a little with length.
    static func roughness(width: CGFloat, length: CGFloat) -> CGFloat {
        min(max(1.2, width * 0.55) + length * 0.008, width * 2 + 6)
    }

    /// A slightly bent stroke from a to b with jittered ends.
    static func line(_ a: CGPoint, _ b: CGPoint, rough: CGFloat, rng: inout RNG, into path: CGMutablePath) {
        let len = a.distance(to: b)
        guard len > 0.5 else { return }
        let nx = -(b.y - a.y) / len, ny = (b.x - a.x) / len
        let start = CGPoint(x: a.x + rng.next() * rough * 0.5, y: a.y + rng.next() * rough * 0.5)
        let end = CGPoint(x: b.x + rng.next() * rough * 0.5, y: b.y + rng.next() * rough * 0.5)
        let bend = rng.next() * rough
        let t = 0.5 + rng.next() * 0.15
        let mid = CGPoint(x: a.x + (b.x - a.x) * t + nx * bend, y: a.y + (b.y - a.y) * t + ny * bend)
        path.move(to: start)
        path.addQuadCurve(to: end, control: mid)
    }

    /// Two passes over each segment.
    static func strokes(_ segments: [(CGPoint, CGPoint)], width: CGFloat, id: UUID) -> CGPath {
        var rng = RNG(id)
        let path = CGMutablePath()
        for (a, b) in segments {
            let rough = roughness(width: width, length: a.distance(to: b))
            line(a, b, rough: rough, rng: &rng, into: path)
            line(a, b, rough: rough * 0.8, rng: &rng, into: path)
        }
        return path
    }

    /// An ellipse drawn as one loop that overshoots its start, then a second lighter loop.
    static func ellipse(in r: CGRect, width: CGFloat, id: UUID) -> CGPath {
        var rng = RNG(id)
        let path = CGMutablePath()
        let rough = roughness(width: width, length: (r.width + r.height) * 0.6)
        for pass in 0..<2 {
            let start = rng.next() * .pi
            let steps = 48
            let sweep = 2 * CGFloat.pi * (pass == 0 ? 1.08 : 1.02)
            let jitter = rough * (pass == 0 ? 1 : 0.7)
            let rx = r.width / 2 + rng.next() * jitter * 0.6, ry = r.height / 2 + rng.next() * jitter * 0.6
            for i in 0...steps {
                let a = start + sweep * CGFloat(i) / CGFloat(steps)
                // Low-frequency wobble so the outline looks drawn, not noisy.
                let w = 1 + 0.012 * sin(a * 3 + CGFloat(pass)) * (jitter / max(1, width))
                let p = CGPoint(x: r.midX + cos(a) * rx * w, y: r.midY + sin(a) * ry * w)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
        return path
    }

    /// Open "V" head at the tip of an arrow from a to b.
    static func arrowHead(from a: CGPoint, to b: CGPoint, width: CGFloat) -> [(CGPoint, CGPoint)] {
        let len = a.distance(to: b)
        guard len > 1 else { return [] }
        let head = min(max(18, width * 6), len * 0.6)
        let angle = atan2(b.y - a.y, b.x - a.x)
        return [-0.5, 0.5].map { (d: CGFloat) in
            let t = angle + .pi + d
            return (b, CGPoint(x: b.x + cos(t) * head, y: b.y + sin(t) * head))
        }
    }
}
