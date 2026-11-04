import SwiftUI

/// Original vector chess set, authored as SVG and drawn through the shared SVG renderer.
@MainActor
enum ChessArt {
    private static var cache: [Int: SVGDocument] = [:]

    static func document(piece: Int8) -> SVGDocument? {
        let key = Int(piece)
        if let d = cache[key] { return d }
        guard let d = SVGDocument(string: svg(type: Int(abs(piece)), white: piece > 0)) else { return nil }
        cache[key] = d
        return d
    }

    private static func svg(type: Int, white: Bool) -> String {
        let top = white ? "#FFFFFF" : "#6B7290", bottom = white ? "#C5CDE0" : "#1D2030"
        let stroke = white ? "#2E3246" : "#05060C"
        let shine = white ? "#FFFFFF" : "#9AA3C7"
        let base = ##"<path d="M24 90 L24 84 Q24 77 32 77 H68 Q76 77 76 84 L76 90 Z"/>"##
        let body: String
        switch type {
        case 1:
            body = ##"<circle cx="50" cy="29" r="13"/><path d="M40 45 Q50 41 60 45 L58 53 Q65 66 69 77 H31 Q35 66 42 53 Z"/>"## + base
        case 2:
            body = ##"<path d="M29 77 C29 57 36 46 47 38 C43 36 40 31 42 26 L40 11 L51 19 C57 15 62 16 64 21 C75 28 75 47 71 57 C69 65 71 71 73 77 Z"/><circle cx="55" cy="30" r="3" fill="\##(stroke)" stroke="none"/><path d="M44 40 Q52 44 58 40" fill="none"/>"## + base
        case 3:
            body = ##"<ellipse cx="50" cy="36" rx="14" ry="20"/><circle cx="50" cy="13" r="5"/><path d="M50 22 V38 M43 30 H57" fill="none"/><rect x="37" y="54" width="26" height="7" rx="3"/><path d="M41 61 H59 L66 77 H34 Z"/>"## + base
        case 4:
            body = ##"<path d="M28 18 H38 V27 H45 V18 H55 V27 H62 V18 H72 V40 L66 46 L68 77 H32 L34 46 L28 40 Z"/><path d="M34 46 H66" fill="none"/>"## + base
        case 5:
            body = ##"<path d="M26 36 L34 65 L38 31 L45 63 L50 27 L55 63 L62 31 L66 65 L74 36 L70 77 H30 Z"/><circle cx="26" cy="32" r="4.5"/><circle cx="38" cy="26" r="4.5"/><circle cx="50" cy="22" r="4.5"/><circle cx="62" cy="26" r="4.5"/><circle cx="74" cy="32" r="4.5"/>"## + base
        default:
            body = ##"<rect x="46" y="8" width="8" height="26" rx="2"/><rect x="38" y="16" width="24" height="8" rx="2"/><path d="M32 77 C27 57 33 41 50 38 C67 41 73 57 68 77 Z"/><path d="M36 54 H64" fill="none"/>"## + base
        }
        return ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><linearGradient id="f" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="\##(top)"/><stop offset="1" stop-color="\##(bottom)"/></linearGradient></defs><ellipse cx="50" cy="91" rx="30" ry="4" fill="#000" opacity="0.28"/><g fill="url(#f)" stroke="\##(stroke)" stroke-width="3" stroke-linejoin="round" stroke-linecap="round">\##(body)</g><path d="M36 80 H64" stroke="\##(shine)" stroke-width="1.6" opacity="0.7" stroke-linecap="round"/></svg>"##
    }
}

struct ChessPieceView: View {
    let piece: Int8
    var size: CGFloat
    var body: some View {
        let doc = ChessArt.document(piece: piece)
        Canvas { ctx, sz in if let doc { SVGRenderer.draw(doc, in: &ctx, size: sz) } }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
