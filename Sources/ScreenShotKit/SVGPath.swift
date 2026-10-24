import CoreGraphics
import Foundation

/// Reads SVG path data (`d="M4 12h15M14 7l5 5-5 5"`) into a CGPath, so the app's icons are drawn from the same path
/// strings as the design files. Handles every command (M L H V C S Q T A Z, absolute and relative), implicit repeats,
/// and compact numbers such as `-.6` and `1.5.8` (two numbers). Throws on anything it can't read.
enum SVGPath {
    enum ParseError: Error, Equatable {
        case unexpected(Character, at: Int)
        case missingNumber(after: Character)
    }

    static func parse(_ d: String) throws -> CGPath {
        var s = Scanner(Array(d.utf8))
        let path = CGMutablePath()
        var current = CGPoint.zero, start = CGPoint.zero
        var lastControl: CGPoint? // for S and T
        var lastCommand: UInt8 = 0
        var command: UInt8 = 0

        while true {
            s.skipSeparators()
            guard let c = s.peek else { break }
            if Scanner.isCommand(c) {
                command = c
                s.index += 1
            } else if command == 0 || !Scanner.startsNumber(c) {
                throw ParseError.unexpected(Character(UnicodeScalar(c)), at: s.index)
            } else if command == UInt8(ascii: "M") {
                command = UInt8(ascii: "L") // numbers after a moveto are linetos
            } else if command == UInt8(ascii: "m") {
                command = UInt8(ascii: "l")
            } else if command == UInt8(ascii: "Z") || command == UInt8(ascii: "z") {
                throw ParseError.unexpected(Character(UnicodeScalar(c)), at: s.index)
            }
            let relative = command >= UInt8(ascii: "a")
            let upper = relative ? command - 32 : command
            let name = Character(UnicodeScalar(command))
            func num() throws -> CGFloat {
                guard let v = s.number() else { throw ParseError.missingNumber(after: name) }
                return v
            }
            func point() throws -> CGPoint {
                let x = try num(), y = try num()
                return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            var control: CGPoint?

            switch upper {
            case UInt8(ascii: "M"):
                current = try point(); start = current
                path.move(to: current)
            case UInt8(ascii: "L"):
                current = try point()
                path.addLine(to: current)
            case UInt8(ascii: "H"):
                let x = try num()
                current.x = relative ? current.x + x : x
                path.addLine(to: current)
            case UInt8(ascii: "V"):
                let y = try num()
                current.y = relative ? current.y + y : y
                path.addLine(to: current)
            case UInt8(ascii: "C"):
                let c1 = try point(), c2 = try point(), end = try point()
                path.addCurve(to: end, control1: c1, control2: c2)
                control = c2; current = end
            case UInt8(ascii: "S"):
                let c1 = reflected(lastControl, current, if: [UInt8(ascii: "C"), UInt8(ascii: "S")], lastCommand)
                let c2 = try point(), end = try point()
                path.addCurve(to: end, control1: c1, control2: c2)
                control = c2; current = end
            case UInt8(ascii: "Q"):
                let c1 = try point(), end = try point()
                path.addQuadCurve(to: end, control: c1)
                control = c1; current = end
            case UInt8(ascii: "T"):
                let c1 = reflected(lastControl, current, if: [UInt8(ascii: "Q"), UInt8(ascii: "T")], lastCommand)
                let end = try point()
                path.addQuadCurve(to: end, control: c1)
                control = c1; current = end
            case UInt8(ascii: "A"):
                let rx = try num(), ry = try num(), rotation = try num()
                guard let large = s.flag(), let sweep = s.flag() else { throw ParseError.missingNumber(after: name) }
                let end = try point()
                addArc(to: path, from: current, to: end, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
                current = end
            case UInt8(ascii: "Z"):
                path.closeSubpath()
                current = start
            default:
                throw ParseError.unexpected(name, at: s.index - 1)
            }
            lastControl = control
            lastCommand = upper
        }
        return path
    }

    private static func reflected(_ control: CGPoint?, _ p: CGPoint, if commands: [UInt8], _ last: UInt8) -> CGPoint {
        guard let control, commands.contains(last) else { return p }
        return CGPoint(x: 2 * p.x - control.x, y: 2 * p.y - control.y)
    }

    /// SVG's endpoint arc as cubic Béziers (SVG 1.1, appendix F.6).
    private static func addArc(to path: CGMutablePath, from p0: CGPoint, to p1: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat,
                               rotation: CGFloat, large: Bool, sweep: Bool) {
        if p0 == p1 { return }
        var rx = abs(rx0), ry = abs(ry0)
        if rx == 0 || ry == 0 { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180, cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy, y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var k = sqrt(max(0, num / den))
        if large == sweep { k = -k }
        let cx1 = k * rx * y1 / ry, cy1 = -k * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi } else if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let t = 4 / 3 * tan(step / 4)
        func onEllipse(_ a: CGFloat) -> CGPoint {
            let x = rx * cos(a), y = ry * sin(a)
            return CGPoint(x: cosPhi * x - sinPhi * y + cx, y: sinPhi * x + cosPhi * y + cy)
        }
        func derivative(_ a: CGFloat) -> CGPoint {
            let x = -rx * sin(a), y = ry * cos(a)
            return CGPoint(x: cosPhi * x - sinPhi * y, y: sinPhi * x + cosPhi * y)
        }
        var a = theta1
        for i in 0..<segments {
            let b = a + step
            let pa = onEllipse(a), pb = i == segments - 1 ? p1 : onEllipse(b)
            let da = derivative(a), db = derivative(b)
            path.addCurve(to: pb, control1: CGPoint(x: pa.x + t * da.x, y: pa.y + t * da.y),
                          control2: CGPoint(x: pb.x - t * db.x, y: pb.y - t * db.y))
            a = b
        }
    }

    /// A cursor over the path data's bytes.
    private struct Scanner {
        let bytes: [UInt8]
        var index = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }

        var peek: UInt8? { index < bytes.count ? bytes[index] : nil }

        static func isCommand(_ c: UInt8) -> Bool { "MmLlHhVvCcSsQqTtAaZz".utf8.contains(c) }
        static func startsNumber(_ c: UInt8) -> Bool { (c >= 48 && c <= 57) || c == 46 || c == 45 || c == 43 }

        mutating func skipSeparators() {
            while let c = peek, c == 32 || c == 44 || c == 9 || c == 10 || c == 13 { index += 1 }
        }

        /// One number: optional sign, digits with at most one dot, optional exponent. A second dot starts the next number.
        mutating func number() -> CGFloat? {
            skipSeparators()
            let begin = index
            if let c = peek, c == 45 || c == 43 { index += 1 }
            var digits = false, dot = false
            while let c = peek {
                if c >= 48 && c <= 57 { digits = true; index += 1 } else if c == 46 && !dot { dot = true; index += 1 } else { break }
            }
            if digits, let c = peek, c == 101 || c == 69 { // e / E
                let save = index
                index += 1
                if let s = peek, s == 45 || s == 43 { index += 1 }
                var expDigits = false
                while let d = peek, d >= 48 && d <= 57 { expDigits = true; index += 1 }
                if !expDigits { index = save }
            }
            guard digits, let text = String(bytes: bytes[begin..<index], encoding: .ascii), let v = Double(text) else {
                index = begin
                return nil
            }
            return CGFloat(v)
        }

        /// An arc flag: a single 0 or 1, which may run straight into the next number ("a2 2 0 011 1").
        mutating func flag() -> Bool? {
            skipSeparators()
            guard let c = peek, c == 48 || c == 49 else { return nil }
            index += 1
            return c == 49
        }
    }
}
