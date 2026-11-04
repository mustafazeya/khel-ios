import SwiftUI

@MainActor
enum AvatarCache {
    private static var docs: [AvatarSpec: SVGDocument] = [:]
    static func document(_ spec: AvatarSpec) -> SVGDocument? {
        let key = spec.clamped
        if let d = docs[key] { return d }
        guard let d = SVGDocument(string: AvatarSVG.document(key)) else { return nil }
        if docs.count > 200 { docs.removeAll() }
        docs[key] = d
        return d
    }
}

/// Draws an avatar from its SVG at any size, crisp at every scale.
struct AvatarView: View {
    let spec: AvatarSpec
    var size: CGFloat = 44
    var ring: Color?
    var square = false

    var body: some View {
        let doc = AvatarCache.document(spec)
        Canvas { ctx, sz in
            if let doc { SVGRenderer.draw(doc, in: &ctx, size: sz) }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: square ? size * 0.28 : size / 2, style: .continuous))
        .overlay {
            if let ring {
                RoundedRectangle(cornerRadius: square ? size * 0.28 : size / 2, style: .continuous)
                    .strokeBorder(ring, lineWidth: max(2, size * 0.06))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack { ForEach(0 ..< 5, id: \.self) { AvatarView(spec: .random(seed: UInt64($0 + 3)), size: 64) } }
        .padding().background(Theme.bg)
}
