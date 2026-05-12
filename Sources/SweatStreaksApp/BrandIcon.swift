import AppKit
import CoreGraphics
import Foundation

enum BrandIcon {
    // Visual weight target: SF Symbols render the glyph in roughly the inner
    // ~80% of their bounding box. We bake that inset into the rendered NSImage
    // so brand marks sit at the same optical size as `Image(systemName:)` next
    // to them in the menu bar and elsewhere in the UI.
    static let github: NSImage = makeImage(svgPath: githubPath, viewBox: 24, inset: 0.8, style: .fill)
    static let leetcode: NSImage = makeImage(svgPath: leetcodePath, viewBox: 24, inset: 0.8, style: .fill)

    enum DrawStyle {
        case fill
        case stroke(lineWidth: CGFloat)
    }

    private static let githubPath = "M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0 0 24 12c0-6.63-5.37-12-12-12z"

    private static let leetcodePath = "M13.483 0a1.374 1.374 0 0 0-.961.438L7.116 6.226l-3.854 4.126a5.266 5.266 0 0 0-1.209 2.104 5.35 5.35 0 0 0-.125.513 5.527 5.527 0 0 0 .062 2.362 5.83 5.83 0 0 0 .349 1.017 5.938 5.938 0 0 0 1.271 1.818l4.277 4.193.039.038c2.248 2.165 5.852 2.133 8.063-.074l2.396-2.392c.54-.54.54-1.414.003-1.955a1.378 1.378 0 0 0-1.951-.003l-2.396 2.392a3.021 3.021 0 0 1-4.205.038l-.02-.019-4.276-4.193c-.652-.64-.972-1.469-.948-2.263a2.68 2.68 0 0 1 .066-.523 2.545 2.545 0 0 1 .619-1.164L9.13 8.114c1.058-1.134 3.204-1.27 4.43-.278l3.501 2.831c.593.48 1.461.387 1.94-.207a1.384 1.384 0 0 0-.207-1.943l-3.5-2.831c-.8-.647-1.766-1.045-2.774-1.202l2.015-2.158A1.384 1.384 0 0 0 13.483 0zm-2.866 12.815a1.38 1.38 0 0 0-1.38 1.382 1.38 1.38 0 0 0 1.38 1.382H20.79a1.38 1.38 0 0 0 1.38-1.382 1.38 1.38 0 0 0-1.38-1.382z"

    private static func makeImage(svgPath: String, viewBox: CGFloat, inset: CGFloat, style: DrawStyle) -> NSImage {
        let parsed = SVGPathParser.parse(svgPath)
        let drawable = pathFittedToInset(parsed, viewBox: viewBox, inset: inset)
        let image = NSImage(size: NSSize(width: viewBox, height: viewBox), flipped: true) { _ in
            switch style {
            case .fill:
                NSColor.black.setFill()
                drawable.fill()
            case .stroke(let lineWidth):
                NSColor.black.setStroke()
                drawable.lineWidth = lineWidth
                drawable.lineCapStyle = .round
                drawable.lineJoinStyle = .round
                drawable.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func pathFittedToInset(_ path: NSBezierPath, viewBox: CGFloat, inset: CGFloat) -> NSBezierPath {
        let bounds = path.bounds
        guard bounds.width > 0, bounds.height > 0 else { return path }

        let target = viewBox - 2 * inset
        let scale = min(target / bounds.width, target / bounds.height)
        let scaledWidth = bounds.width * scale
        let scaledHeight = bounds.height * scale
        let tx = (viewBox - scaledWidth) / 2 - bounds.minX * scale
        let ty = (viewBox - scaledHeight) / 2 - bounds.minY * scale

        var transform = AffineTransform.identity
        transform.translate(x: tx, y: ty)
        transform.scale(scale)

        guard let copy = path.copy() as? NSBezierPath else { return path }
        copy.transform(using: transform)
        return copy
    }
}

// MARK: - SVG path parser

private struct SVGPathParser {
    static func parse(_ d: String) -> NSBezierPath {
        var parser = SVGPathParser(source: Array(d))
        parser.run()
        return parser.path
    }

    private let source: [Character]
    private var index = 0
    private var current = CGPoint.zero
    private var subpathStart = CGPoint.zero
    private var lastControl: CGPoint?
    private var lastCommand: Character = " "
    private(set) var path = NSBezierPath()

    private init(source: [Character]) {
        self.source = source
    }

    private mutating func run() {
        while index < source.count {
            skipSeparators()
            guard index < source.count else { break }
            let c = source[index]
            if c.isLetter {
                index += 1
                execute(command: c)
            } else {
                execute(command: implicitContinuation(of: lastCommand))
            }
        }
    }

    private mutating func execute(command cmd: Character) {
        switch cmd {
        case "M":
            let p = readPoint()
            path.move(to: p)
            current = p
            subpathStart = p
            while hasMoreNumbers() {
                let q = readPoint()
                path.line(to: q)
                current = q
            }
        case "m":
            let dp = readPoint()
            let p = CGPoint(x: current.x + dp.x, y: current.y + dp.y)
            path.move(to: p)
            current = p
            subpathStart = p
            while hasMoreNumbers() {
                let dq = readPoint()
                let q = CGPoint(x: current.x + dq.x, y: current.y + dq.y)
                path.line(to: q)
                current = q
            }
        case "L":
            while hasMoreNumbers() {
                let p = readPoint()
                path.line(to: p)
                current = p
            }
        case "l":
            while hasMoreNumbers() {
                let dp = readPoint()
                let p = CGPoint(x: current.x + dp.x, y: current.y + dp.y)
                path.line(to: p)
                current = p
            }
        case "H":
            while hasMoreNumbers() {
                let x = readNumber()
                let p = CGPoint(x: x, y: current.y)
                path.line(to: p)
                current = p
            }
        case "h":
            while hasMoreNumbers() {
                let dx = readNumber()
                let p = CGPoint(x: current.x + dx, y: current.y)
                path.line(to: p)
                current = p
            }
        case "V":
            while hasMoreNumbers() {
                let y = readNumber()
                let p = CGPoint(x: current.x, y: y)
                path.line(to: p)
                current = p
            }
        case "v":
            while hasMoreNumbers() {
                let dy = readNumber()
                let p = CGPoint(x: current.x, y: current.y + dy)
                path.line(to: p)
                current = p
            }
        case "C":
            while hasMoreNumbers() {
                let c1 = readPoint()
                let c2 = readPoint()
                let p = readPoint()
                path.curve(to: p, controlPoint1: c1, controlPoint2: c2)
                lastControl = c2
                current = p
            }
        case "c":
            while hasMoreNumbers() {
                let d1 = readPoint()
                let d2 = readPoint()
                let dp = readPoint()
                let c1 = CGPoint(x: current.x + d1.x, y: current.y + d1.y)
                let c2 = CGPoint(x: current.x + d2.x, y: current.y + d2.y)
                let p = CGPoint(x: current.x + dp.x, y: current.y + dp.y)
                path.curve(to: p, controlPoint1: c1, controlPoint2: c2)
                lastControl = c2
                current = p
            }
        case "S":
            while hasMoreNumbers() {
                let c2 = readPoint()
                let p = readPoint()
                let c1 = reflectedControl()
                path.curve(to: p, controlPoint1: c1, controlPoint2: c2)
                lastControl = c2
                current = p
            }
        case "s":
            while hasMoreNumbers() {
                let d2 = readPoint()
                let dp = readPoint()
                let c2 = CGPoint(x: current.x + d2.x, y: current.y + d2.y)
                let p = CGPoint(x: current.x + dp.x, y: current.y + dp.y)
                let c1 = reflectedControl()
                path.curve(to: p, controlPoint1: c1, controlPoint2: c2)
                lastControl = c2
                current = p
            }
        case "Q":
            while hasMoreNumbers() {
                let qc = readPoint()
                let p = readPoint()
                appendQuadratic(qc: qc, end: p)
            }
        case "q":
            while hasMoreNumbers() {
                let dqc = readPoint()
                let dp = readPoint()
                let qc = CGPoint(x: current.x + dqc.x, y: current.y + dqc.y)
                let p = CGPoint(x: current.x + dp.x, y: current.y + dp.y)
                appendQuadratic(qc: qc, end: p)
            }
        case "T":
            while hasMoreNumbers() {
                let p = readPoint()
                let qc = reflectedQuadraticControl()
                appendQuadratic(qc: qc, end: p)
            }
        case "t":
            while hasMoreNumbers() {
                let dp = readPoint()
                let p = CGPoint(x: current.x + dp.x, y: current.y + dp.y)
                let qc = reflectedQuadraticControl()
                appendQuadratic(qc: qc, end: p)
            }
        case "A":
            while hasMoreNumbers() {
                let rx = readNumber()
                let ry = readNumber()
                let phi = readNumber()
                let large = readFlag()
                let sweep = readFlag()
                let end = readPoint()
                appendArc(from: current, to: end, rx: rx, ry: ry, xRotDeg: phi, largeArc: large, sweep: sweep)
                current = end
            }
        case "a":
            while hasMoreNumbers() {
                let rx = readNumber()
                let ry = readNumber()
                let phi = readNumber()
                let large = readFlag()
                let sweep = readFlag()
                let dp = readPoint()
                let end = CGPoint(x: current.x + dp.x, y: current.y + dp.y)
                appendArc(from: current, to: end, rx: rx, ry: ry, xRotDeg: phi, largeArc: large, sweep: sweep)
                current = end
            }
        case "Z", "z":
            path.close()
            current = subpathStart
        default:
            break
        }
        lastCommand = cmd
    }

    private mutating func appendQuadratic(qc: CGPoint, end: CGPoint) {
        let c1 = CGPoint(x: current.x + 2.0 / 3.0 * (qc.x - current.x),
                         y: current.y + 2.0 / 3.0 * (qc.y - current.y))
        let c2 = CGPoint(x: end.x + 2.0 / 3.0 * (qc.x - end.x),
                         y: end.y + 2.0 / 3.0 * (qc.y - end.y))
        path.curve(to: end, controlPoint1: c1, controlPoint2: c2)
        lastControl = qc
        current = end
    }

    private func reflectedControl() -> CGPoint {
        let prevWasCubic = "CcSs".contains(lastCommand)
        guard prevWasCubic, let lc = lastControl else { return current }
        return CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
    }

    private func reflectedQuadraticControl() -> CGPoint {
        let prevWasQuad = "QqTt".contains(lastCommand)
        guard prevWasQuad, let lc = lastControl else { return current }
        return CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
    }

    // SVG arc to cubic Beziers (per https://www.w3.org/TR/SVG/implnote.html#ArcImplementationNotes)
    private mutating func appendArc(from p1: CGPoint, to p2: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat, xRotDeg: CGFloat, largeArc: Bool, sweep: Bool) {
        if p1 == p2 { return }
        if rxIn == 0 || ryIn == 0 {
            path.line(to: p2)
            return
        }
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        let phi = xRotDeg * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx = (p1.x - p2.x) / 2
        let dy = (p1.y - p2.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s
            ry *= s
        }

        let sign: CGFloat = (largeArc == sweep) ? -1 : 1
        let num = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coef = sign * sqrt(num / den)
        let cxp = coef * (rx * y1p) / ry
        let cyp = coef * -(ry * x1p) / rx

        let cx = cosPhi * cxp - sinPhi * cyp + (p1.x + p2.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p1.y + p2.y) / 2

        let theta1 = angle(ux: 1, uy: 0,
                           vx: (x1p - cxp) / rx,
                           vy: (y1p - cyp) / ry)
        var delta = angle(ux: (x1p - cxp) / rx,
                          uy: (y1p - cyp) / ry,
                          vx: (-x1p - cxp) / rx,
                          vy: (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        // Split the arc into segments of <= 90° and approximate each with a cubic Bezier
        let segmentCount = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let segDelta = delta / CGFloat(segmentCount)
        let alpha = sin(segDelta) * (sqrt(4 + 3 * pow(tan(segDelta / 2), 2)) - 1) / 3

        var theta = theta1
        for _ in 0..<segmentCount {
            let theta2 = theta + segDelta
            let e1 = ellipsePoint(cx: cx, cy: cy, rx: rx, ry: ry, phi: phi, theta: theta)
            let e2 = ellipsePoint(cx: cx, cy: cy, rx: rx, ry: ry, phi: phi, theta: theta2)
            let e1d = ellipseDerivative(rx: rx, ry: ry, phi: phi, theta: theta)
            let e2d = ellipseDerivative(rx: rx, ry: ry, phi: phi, theta: theta2)
            let c1 = CGPoint(x: e1.x + alpha * e1d.x, y: e1.y + alpha * e1d.y)
            let c2 = CGPoint(x: e2.x - alpha * e2d.x, y: e2.y - alpha * e2d.y)
            path.curve(to: e2, controlPoint1: c1, controlPoint2: c2)
            theta = theta2
        }
    }

    private func ellipsePoint(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, phi: CGFloat, theta: CGFloat) -> CGPoint {
        let cosT = cos(theta)
        let sinT = sin(theta)
        return CGPoint(
            x: cx + cos(phi) * rx * cosT - sin(phi) * ry * sinT,
            y: cy + sin(phi) * rx * cosT + cos(phi) * ry * sinT
        )
    }

    private func ellipseDerivative(rx: CGFloat, ry: CGFloat, phi: CGFloat, theta: CGFloat) -> CGPoint {
        let cosT = cos(theta)
        let sinT = sin(theta)
        return CGPoint(
            x: -cos(phi) * rx * sinT - sin(phi) * ry * cosT,
            y: -sin(phi) * rx * sinT + cos(phi) * ry * cosT
        )
    }

    private func angle(ux: CGFloat, uy: CGFloat, vx: CGFloat, vy: CGFloat) -> CGFloat {
        let dot = ux * vx + uy * vy
        let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
        var a = acos(max(-1, min(1, dot / len)))
        if ux * vy - uy * vx < 0 { a = -a }
        return a
    }

    private func implicitContinuation(of cmd: Character) -> Character {
        switch cmd {
        case "M": return "L"
        case "m": return "l"
        default: return cmd
        }
    }

    // MARK: - Tokenizer

    private mutating func skipSeparators() {
        while index < source.count {
            let c = source[index]
            if c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" {
                index += 1
            } else {
                break
            }
        }
    }

    private mutating func hasMoreNumbers() -> Bool {
        skipSeparators()
        guard index < source.count else { return false }
        let c = source[index]
        return c.isNumber || c == "-" || c == "+" || c == "."
    }

    private mutating func readNumber() -> CGFloat {
        skipSeparators()
        var s = ""
        if index < source.count, source[index] == "-" || source[index] == "+" {
            s.append(source[index])
            index += 1
        }
        var sawDot = false
        var sawE = false
        while index < source.count {
            let c = source[index]
            if c.isNumber {
                s.append(c)
                index += 1
            } else if c == "." && !sawDot && !sawE {
                s.append(c)
                index += 1
                sawDot = true
            } else if (c == "e" || c == "E") && !sawE {
                s.append(c)
                index += 1
                sawE = true
                if index < source.count, source[index] == "-" || source[index] == "+" {
                    s.append(source[index])
                    index += 1
                }
            } else {
                break
            }
        }
        return CGFloat(Double(s) ?? 0)
    }

    private mutating func readPoint() -> CGPoint {
        let x = readNumber()
        let y = readNumber()
        return CGPoint(x: x, y: y)
    }

    private mutating func readFlag() -> Bool {
        skipSeparators()
        guard index < source.count else { return false }
        let c = source[index]
        index += 1
        return c == "1"
    }
}
