import SwiftUI

// MARK: - Path data

/// Parser for SVG path data (`d` attribute): M L H V C S Q T A Z, absolute and relative.
enum SVGPathParser {
    static func parse(_ d: String) -> Path {
        var tokens = Tokenizer(Array(d.unicodeScalars))
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?
        var command: Character = "M"

        while let next = tokens.peekCommand() ?? (tokens.hasNumber ? command : nil) {
            if tokens.peekCommand() != nil { tokens.advanceCommand() }
            command = next
            let rel = command.isLowercase
            let c = Character(command.uppercased())
            func pt(_ x: Double, _ y: Double) -> CGPoint { rel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y) }

            switch c {
            case "Z":
                path.closeSubpath()
                current = start
                lastCubicControl = nil; lastQuadControl = nil
                if !tokens.hasNumber { continue }
            case "M":
                guard let x = tokens.number(), let y = tokens.number() else { return path }
                current = pt(x, y); start = current
                path.move(to: current)
                command = rel ? "l" : "L"
                lastCubicControl = nil; lastQuadControl = nil
            case "L":
                guard let x = tokens.number(), let y = tokens.number() else { return path }
                current = pt(x, y); path.addLine(to: current)
                lastCubicControl = nil; lastQuadControl = nil
            case "H":
                guard let x = tokens.number() else { return path }
                current = CGPoint(x: rel ? current.x + x : x, y: current.y); path.addLine(to: current)
                lastCubicControl = nil; lastQuadControl = nil
            case "V":
                guard let y = tokens.number() else { return path }
                current = CGPoint(x: current.x, y: rel ? current.y + y : y); path.addLine(to: current)
                lastCubicControl = nil; lastQuadControl = nil
            case "C":
                guard let a = tokens.number(), let b = tokens.number(), let c2 = tokens.number(), let d2 = tokens.number(),
                      let x = tokens.number(), let y = tokens.number() else { return path }
                let p1 = pt(a, b), p2 = pt(c2, d2), p = pt(x, y)
                path.addCurve(to: p, control1: p1, control2: p2)
                current = p; lastCubicControl = p2; lastQuadControl = nil
            case "S":
                guard let c2 = tokens.number(), let d2 = tokens.number(), let x = tokens.number(), let y = tokens.number() else { return path }
                let p1 = lastCubicControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let p2 = pt(c2, d2), p = pt(x, y)
                path.addCurve(to: p, control1: p1, control2: p2)
                current = p; lastCubicControl = p2; lastQuadControl = nil
            case "Q":
                guard let a = tokens.number(), let b = tokens.number(), let x = tokens.number(), let y = tokens.number() else { return path }
                let q = pt(a, b), p = pt(x, y)
                path.addQuadCurve(to: p, control: q)
                current = p; lastQuadControl = q; lastCubicControl = nil
            case "T":
                guard let x = tokens.number(), let y = tokens.number() else { return path }
                let q = lastQuadControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let p = pt(x, y)
                path.addQuadCurve(to: p, control: q)
                current = p; lastQuadControl = q; lastCubicControl = nil
            case "A":
                guard let rx = tokens.number(), let ry = tokens.number(), let rot = tokens.number(),
                      let large = tokens.flag(), let sweep = tokens.flag(), let x = tokens.number(), let y = tokens.number() else { return path }
                let p = pt(x, y)
                addArc(to: &path, from: current, to: p, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
                current = p; lastCubicControl = nil; lastQuadControl = nil
            default:
                return path
            }
        }
        return path
    }

    /// Endpoint arc → cubic Béziers (SVG 1.1 implementation notes, F.6).
    private static func addArc(to path: inout Path, from p0: CGPoint, to p1: CGPoint, rx rxIn: Double, ry ryIn: Double,
                               rotation: Double, large: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        guard p0 != p1 else { return }
        guard rx > 0, ry > 0 else { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { let s = sqrt(lambda); rx *= s; ry *= s }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = den == 0 ? 0 : sqrt(max(0, num / den))
        if large == sweep { coef = -coef }
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * (-ry * x1p / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / Double(segments)
        let t = 4.0 / 3.0 * tan(step / 4)
        var a = theta1
        for _ in 0 ..< segments {
            let cosA = cos(a), sinA = sin(a), cosB = cos(a + step), sinB = sin(a + step)
            func map(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: cosPhi * rx * x - sinPhi * ry * y + cx, y: sinPhi * rx * x + cosPhi * ry * y + cy)
            }
            path.addCurve(to: map(cosB, sinB),
                          control1: map(cosA - t * sinA, sinA + t * cosA),
                          control2: map(cosB + t * sinB, sinB - t * cosB))
            a += step
        }
    }

    private struct Tokenizer {
        let chars: [Unicode.Scalar]
        var i = 0
        init(_ chars: [Unicode.Scalar]) { self.chars = chars }

        private mutating func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" || chars[i] == "\r" { i += 1 }
        }

        mutating func peekCommand() -> Character? {
            skipSeparators()
            guard i < chars.count else { return nil }
            let c = Character(chars[i])
            return "MmLlHhVvCcSsQqTtAaZz".contains(c) ? c : nil
        }

        mutating func advanceCommand() { skipSeparators(); i += 1 }

        var hasNumber: Bool {
            mutating get {
                skipSeparators()
                guard i < chars.count else { return false }
                let c = chars[i]
                return (c >= "0" && c <= "9") || c == "-" || c == "+" || c == "."
            }
        }

        mutating func number() -> Double? {
            skipSeparators()
            guard i < chars.count else { return nil }
            var s = ""
            if chars[i] == "-" || chars[i] == "+" { s.unicodeScalars.append(chars[i]); i += 1 }
            var seenDot = false, seenDigit = false
            while i < chars.count {
                let c = chars[i]
                if c >= "0" && c <= "9" { s.unicodeScalars.append(c); i += 1; seenDigit = true }
                else if c == "." && !seenDot { seenDot = true; s.unicodeScalars.append(c); i += 1 }
                else if (c == "e" || c == "E") && seenDigit {
                    s.unicodeScalars.append(c); i += 1
                    if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.unicodeScalars.append(chars[i]); i += 1 }
                } else { break }
            }
            return Double(s)
        }

        /// Arc flags may be written without separators ("a1 1 0 00.5.5").
        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < chars.count, chars[i] == "0" || chars[i] == "1" else { return nil }
            defer { i += 1 }
            return chars[i] == "1"
        }
    }
}

// MARK: - Document model

struct SVGStyle {
    var fill: SVGPaint = .color(.black)
    var stroke: SVGPaint = .none
    var strokeWidth: CGFloat = 1
    var lineCap: CGLineCap = .butt
    var lineJoin: CGLineJoin = .miter
    var fillOpacity: Double = 1
    var strokeOpacity: Double = 1
    var evenOdd = false
}

enum SVGPaint {
    case none
    case color(Color)
    case ref(String)
}

struct SVGGradient {
    struct Stop { var offset: Double; var color: Color; var opacity: Double }
    var radial: Bool
    var userSpace: Bool
    var x1 = 0.0, y1 = 0.0, x2 = 1.0, y2 = 0.0
    var cx = 0.5, cy = 0.5, r = 0.5
    var stops: [Stop] = []
}

final class SVGNode {
    var tag: String
    var attrs: [String: String]
    var children: [SVGNode] = []
    init(tag: String, attrs: [String: String]) { self.tag = tag; self.attrs = attrs }
}

/// A parsed SVG document, ready to be drawn into a SwiftUI `GraphicsContext`.
/// Supported: svg, g, rect, circle, ellipse, line, polyline, polygon, path, defs, linearGradient, radialGradient,
/// clipPath, stop; fill/stroke (colour or gradient), opacity, transform, clip-path, inline `style`.
final class SVGDocument: @unchecked Sendable {
    let root: SVGNode
    let viewBox: CGRect
    private(set) var gradients: [String: SVGGradient] = [:]
    private(set) var clipPaths: [String: SVGNode] = [:]

    init?(string: String) {
        guard let data = string.data(using: .utf8) else { return nil }
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        guard parser.parse(), let root = builder.root, root.tag == "svg" else { return nil }
        self.root = root
        if let vb = root.attrs["viewBox"] {
            let n = vb.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            viewBox = n.count == 4 ? CGRect(x: n[0], y: n[1], width: n[2], height: n[3]) : CGRect(x: 0, y: 0, width: 100, height: 100)
        } else {
            let w = Double(root.attrs["width"] ?? "") ?? 100, h = Double(root.attrs["height"] ?? "") ?? 100
            viewBox = CGRect(x: 0, y: 0, width: w, height: h)
        }
        collect(root)
    }

    private func collect(_ node: SVGNode) {
        let attrs = Self.merged(node)
        if let id = attrs["id"] {
            switch node.tag {
            case "linearGradient", "radialGradient":
                var g = SVGGradient(radial: node.tag == "radialGradient", userSpace: attrs["gradientUnits"] == "userSpaceOnUse")
                func frac(_ key: String, _ def: Double) -> Double {
                    guard var v = attrs[key] else { return def }
                    var scale = 1.0
                    if v.hasSuffix("%") { v.removeLast(); scale = 0.01 }
                    return (Double(v) ?? def) * scale
                }
                g.x1 = frac("x1", 0); g.y1 = frac("y1", 0); g.x2 = frac("x2", 1); g.y2 = frac("y2", 0)
                g.cx = frac("cx", 0.5); g.cy = frac("cy", 0.5); g.r = frac("r", 0.5)
                for stop in node.children where stop.tag == "stop" {
                    let sa = Self.merged(stop)
                    var off = 0.0
                    if var o = sa["offset"] { var s = 1.0; if o.hasSuffix("%") { o.removeLast(); s = 0.01 }; off = (Double(o) ?? 0) * s }
                    g.stops.append(.init(offset: min(max(off, 0), 1), color: SVGColor.parse(sa["stop-color"] ?? "#000") ?? .black,
                                         opacity: Double(sa["stop-opacity"] ?? "") ?? 1))
                }
                gradients[id] = g
            case "clipPath": clipPaths[id] = node
            default: break
            }
        }
        for c in node.children { collect(c) }
    }

    /// Presentation attributes plus the inline `style="a:b;c:d"` declarations.
    static func merged(_ node: SVGNode) -> [String: String] {
        var a = node.attrs
        if let style = a["style"] {
            for decl in style.split(separator: ";") {
                let kv = decl.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if kv.count == 2 { a[kv[0]] = kv[1] }
            }
        }
        return a
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: SVGNode?
        var stack: [SVGNode] = []
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            let node = SVGNode(tag: name, attrs: attributes)
            if let top = stack.last { top.children.append(node) } else { root = node }
            stack.append(node)
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { _ = stack.popLast() }
    }
}

enum SVGColor {
    static func parse(_ raw: String) -> Color? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        switch s {
        case "white": return .white
        case "black": return .black
        case "red": return .red
        case "transparent": return .clear
        default: break
        }
        guard s.hasPrefix("#") else { return nil }
        var hex = String(s.dropFirst())
        if hex.count == 3 || hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, let v = UInt64(hex, radix: 16) else { return nil }
        let a = hex.count == 8 ? Double(v & 255) / 255 : 1
        let rgb = hex.count == 8 ? v >> 8 : v
        return Color(.sRGB, red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, opacity: a)
    }
}

// MARK: - Renderer

enum SVGRenderer {
    /// Draw `doc` fitted and centred inside `size` (preserveAspectRatio "xMidYMid meet").
    static func draw(_ doc: SVGDocument, in context: inout GraphicsContext, size: CGSize) {
        let vb = doc.viewBox
        guard vb.width > 0, vb.height > 0, size.width > 0, size.height > 0 else { return }
        let scale = min(size.width / vb.width, size.height / vb.height)
        var c = context
        c.translateBy(x: (size.width - vb.width * scale) / 2, y: (size.height - vb.height * scale) / 2)
        c.scaleBy(x: scale, y: scale)
        c.translateBy(x: -vb.minX, y: -vb.minY)
        render(doc.root, doc: doc, style: SVGStyle(), context: &c)
    }

    private static func render(_ node: SVGNode, doc: SVGDocument, style parent: SVGStyle, context: inout GraphicsContext) {
        let a = SVGDocument.merged(node)
        if ["defs", "linearGradient", "radialGradient", "clipPath", "stop", "title", "desc"].contains(node.tag) { return }
        if a["display"] == "none" { return }

        var style = parent
        if let f = a["fill"] { style.fill = paint(f) }
        if let s = a["stroke"] { style.stroke = paint(s) }
        if let w = a["stroke-width"], let v = Double(w) { style.strokeWidth = v }
        if let v = a["fill-opacity"], let d = Double(v) { style.fillOpacity = d }
        if let v = a["stroke-opacity"], let d = Double(v) { style.strokeOpacity = d }
        if let v = a["stroke-linecap"] { style.lineCap = v == "round" ? .round : v == "square" ? .square : .butt }
        if let v = a["stroke-linejoin"] { style.lineJoin = v == "round" ? .round : v == "bevel" ? .bevel : .miter }
        if let v = a["fill-rule"] { style.evenOdd = v == "evenodd" }

        var c = context
        if let t = a["transform"] { c.concatenate(Transform.parse(t)) }
        if let o = a["opacity"], let d = Double(o) { c.opacity *= d }
        if let clip = a["clip-path"], let id = urlID(clip), let clipNode = doc.clipPaths[id] {
            var clipPath = Path()
            for child in clipNode.children { if let p = shapePath(child) { clipPath.addPath(p) } }
            c.clip(to: clipPath)
        }

        if node.tag == "svg" || node.tag == "g" {
            for child in node.children { render(child, doc: doc, style: style, context: &c) }
            return
        }
        guard let path = shapePath(node) else { return }
        paintPath(path, style: style, doc: doc, context: &c)
    }

    private static func paintPath(_ path: Path, style: SVGStyle, doc: SVGDocument, context c: inout GraphicsContext) {
        if let shading = shading(style.fill, opacity: style.fillOpacity, bounds: path.boundingRect, doc: doc) {
            c.fill(path, with: shading, style: FillStyle(eoFill: style.evenOdd))
        }
        if style.strokeWidth > 0, let shading = shading(style.stroke, opacity: style.strokeOpacity, bounds: path.boundingRect, doc: doc) {
            c.stroke(path, with: shading, style: StrokeStyle(lineWidth: style.strokeWidth, lineCap: style.lineCap, lineJoin: style.lineJoin))
        }
    }

    private static func paint(_ value: String) -> SVGPaint {
        let v = value.trimmingCharacters(in: .whitespaces)
        if v == "none" { return .none }
        if let id = urlID(v) { return .ref(id) }
        if let c = SVGColor.parse(v) { return .color(c) }
        return .none
    }

    private static func urlID(_ v: String) -> String? {
        guard v.hasPrefix("url(#"), let end = v.firstIndex(of: ")") else { return nil }
        return String(v[v.index(v.startIndex, offsetBy: 5) ..< end])
    }

    private static func shading(_ paint: SVGPaint, opacity: Double, bounds: CGRect, doc: SVGDocument) -> GraphicsContext.Shading? {
        switch paint {
        case .none: return nil
        case .color(let c): return .color(c.opacity(opacity))
        case .ref(let id):
            guard let g = doc.gradients[id], !g.stops.isEmpty else { return nil }
            let gradient = Gradient(stops: g.stops.map { .init(color: $0.color.opacity($0.opacity * opacity), location: $0.offset) })
            func map(_ x: Double, _ y: Double) -> CGPoint {
                g.userSpace ? CGPoint(x: x, y: y) : CGPoint(x: bounds.minX + x * bounds.width, y: bounds.minY + y * bounds.height)
            }
            if g.radial {
                let radius = g.userSpace ? g.r : g.r * max(bounds.width, bounds.height)
                return .radialGradient(gradient, center: map(g.cx, g.cy), startRadius: 0, endRadius: radius)
            }
            return .linearGradient(gradient, startPoint: map(g.x1, g.y1), endPoint: map(g.x2, g.y2))
        }
    }

    private static func shapePath(_ node: SVGNode) -> Path? {
        let a = SVGDocument.merged(node)
        func num(_ k: String, _ d: Double = 0) -> Double { Double(a[k]?.replacingOccurrences(of: "px", with: "") ?? "") ?? d }
        switch node.tag {
        case "path": return a["d"].map(SVGPathParser.parse)
        case "rect":
            let r = CGRect(x: num("x"), y: num("y"), width: num("width"), height: num("height"))
            let rx = a["rx"] != nil ? num("rx") : num("ry"), ry = a["ry"] != nil ? num("ry") : num("rx")
            return rx > 0 || ry > 0 ? Path(roundedRect: r, cornerSize: CGSize(width: rx, height: ry)) : Path(r)
        case "circle":
            let r = num("r")
            return Path(ellipseIn: CGRect(x: num("cx") - r, y: num("cy") - r, width: 2 * r, height: 2 * r))
        case "ellipse":
            return Path(ellipseIn: CGRect(x: num("cx") - num("rx"), y: num("cy") - num("ry"), width: 2 * num("rx"), height: 2 * num("ry")))
        case "line":
            var p = Path(); p.move(to: CGPoint(x: num("x1"), y: num("y1"))); p.addLine(to: CGPoint(x: num("x2"), y: num("y2"))); return p
        case "polyline", "polygon":
            let n = (a["points"] ?? "").split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            guard n.count >= 4 else { return nil }
            var p = Path()
            p.move(to: CGPoint(x: n[0], y: n[1]))
            for i in stride(from: 2, to: n.count - 1, by: 2) { p.addLine(to: CGPoint(x: n[i], y: n[i + 1])) }
            if node.tag == "polygon" { p.closeSubpath() }
            return p
        default: return nil
        }
    }

    private enum Transform {
        static func parse(_ s: String) -> CGAffineTransform {
            var result = CGAffineTransform.identity
            var rest = Substring(s)
            while let open = rest.firstIndex(of: "("), let close = rest.firstIndex(of: ")") {
                let name = rest[rest.startIndex ..< open].trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
                let n = rest[rest.index(after: open) ..< close].split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
                var t = CGAffineTransform.identity
                switch name {
                case "translate": t = CGAffineTransform(translationX: n.first ?? 0, y: n.count > 1 ? n[1] : 0)
                case "scale": t = CGAffineTransform(scaleX: n.first ?? 1, y: n.count > 1 ? n[1] : (n.first ?? 1))
                case "rotate":
                    let r = (n.first ?? 0) * .pi / 180
                    if n.count == 3 {
                        t = CGAffineTransform(translationX: n[1], y: n[2]).rotated(by: r).translatedBy(x: -n[1], y: -n[2])
                    } else { t = CGAffineTransform(rotationAngle: r) }
                case "skewX": t = CGAffineTransform(a: 1, b: 0, c: tan((n.first ?? 0) * .pi / 180), d: 1, tx: 0, ty: 0)
                case "skewY": t = CGAffineTransform(a: 1, b: tan((n.first ?? 0) * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
                case "matrix": if n.count == 6 { t = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5]) }
                default: break
                }
                result = t.concatenating(result)
                rest = rest[rest.index(after: close)...]
            }
            return result
        }
    }
}

private extension GraphicsContext {
    mutating func concatenate(_ t: CGAffineTransform) { transform = t.concatenating(transform) }
}
