import Foundation

/// Turns an `AvatarSpec` into a standalone SVG document (200 × 200 viewBox).
/// The output is plain SVG 1.1 that any browser or design tool opens, and it is what the in-app renderer draws.
enum AvatarSVG {
    static func document(_ spec: AvatarSpec) -> String {
        let s = spec.clamped
        let skin = AvatarSpec.skinTones[s.skin]
        let shade = mix(skin, with: "#000000", 0.14)
        let hair = AvatarSpec.hairColors[s.hairColor]
        let hairDark = mix(hair, with: "#000000", 0.25)
        let cloth = AvatarSpec.clothingColors[s.clothingColor]
        let clothDark = mix(cloth, with: "#000000", 0.22)
        let clothLight = mix(cloth, with: "#FFFFFF", 0.35)
        let pair = AvatarSpec.backgroundPairs[s.backgroundColor]

        var out = ""
        out += ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200" width="200" height="200">"##
        out += defs(s, pair: pair)
        out += background(s, pair: pair)
        out += hairBack(s, hair: hair)
        out += ##"<path d="M82 128 L82 158 C82 170 118 170 118 158 L118 128 Z" fill="\##(shade)"/>"##
        out += body(s, cloth: cloth, dark: clothDark, light: clothLight)
        out += ##"<ellipse cx="100" cy="142" rx="30" ry="13" fill="\##(shade)" opacity="0.55"/>"##
        out += ears(s, skin: skin, shade: shade)
        out += head(s, skin: skin)
        out += face(s, hair: hair, hairDark: hairDark, shade: shade)
        out += hairFront(s, hair: hair, dark: hairDark)
        out += headwear(s, cloth: cloth, dark: clothDark, light: clothLight)
        out += glasses(s)
        out += "</svg>"
        return out
    }

    // MARK: Colour helpers

    static func mix(_ a: String, with b: String, _ t: Double) -> String {
        func rgb(_ h: String) -> (Double, Double, Double) {
            let v = UInt32(h.dropFirst(), radix: 16) ?? 0
            return (Double((v >> 16) & 255), Double((v >> 8) & 255), Double(v & 255))
        }
        let (r1, g1, b1) = rgb(a), (r2, g2, b2) = rgb(b)
        func ch(_ x: Double, _ y: Double) -> Int { Int((x + (y - x) * t).rounded()) }
        return String(format: "#%02X%02X%02X", ch(r1, r2), ch(g1, g2), ch(b1, b2))
    }

    // MARK: Layers

    private static func defs(_ s: AvatarSpec, pair: (String, String)) -> String {
        """
        <defs>
        <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="\(pair.0)"/><stop offset="1" stop-color="\(pair.1)"/></linearGradient>
        <radialGradient id="glow" cx="0.5" cy="0.4" r="0.7"><stop offset="0" stop-color="\(pair.0)"/><stop offset="1" stop-color="\(pair.1)"/></radialGradient>
        <clipPath id="body"><path d="M30 200 C30 160 60 150 82 148 Q100 168 118 148 C140 150 170 160 170 200 Z"/></clipPath>
        </defs>
        """
    }

    private static func background(_ s: AvatarSpec, pair: (String, String)) -> String {
        switch s.background {
        case 0: return ##"<rect width="200" height="200" fill="url(#bg)"/>"##
        case 1: return ##"<rect width="200" height="200" fill="url(#glow)"/>"##
        case 2:
            var t = ##"<rect width="200" height="200" fill="\##(pair.0)"/><g transform="rotate(-30 100 100)" fill="\##(pair.1)" opacity="0.45">"##
            for i in stride(from: -60, to: 280, by: 40) { t += ##"<rect x="\##(i)" y="-60" width="20" height="320"/>"## }
            return t + "</g>"
        default:
            var t = ##"<rect width="200" height="200" fill="\##(pair.1)"/><g fill="\##(pair.0)" opacity="0.5">"##
            for row in 0 ..< 6 { for col in 0 ..< 6 {
                t += ##"<circle cx="\##(20 + col * 32 + (row % 2) * 16)" cy="\##(16 + row * 34)" r="6"/>"##
            } }
            return t + "</g>"
        }
    }

    private static func hairBack(_ s: AvatarSpec, hair: String) -> String {
        switch s.hair {
        case 4: ##"<path d="M46 92 C36 140 40 176 58 188 L142 188 C160 176 164 140 154 92 Z" fill="\##(hair)"/>"##
        case 7: ##"<circle cx="100" cy="82" r="64" fill="\##(hair)"/>"##
        default: ""
        }
    }

    private static func body(_ s: AvatarSpec, cloth: String, dark: String, light: String) -> String {
        let base = ##"<path d="M30 200 C30 160 60 150 82 148 Q100 168 118 148 C140 150 170 160 170 200 Z" fill="\##(cloth)"/>"##
        switch s.clothing {
        case 1:
            return base + ##"<path d="M82 146 L84 160 L100 168 L116 160 L118 146 Q100 166 82 146 Z" fill="\##(dark)"/><path d="M100 168 L100 200" stroke="\##(dark)" stroke-width="3"/><circle cx="100" cy="178" r="3" fill="#FDE68A"/><circle cx="100" cy="192" r="3" fill="#FDE68A"/>"##
        case 2:
            return base + ##"<path d="M66 154 C66 176 134 176 134 154 C128 144 116 150 100 156 C84 150 72 144 66 154 Z" fill="\##(dark)"/><path d="M90 164 L88 192 M110 164 L112 192" stroke="#FFFFFF" stroke-width="3" stroke-linecap="round" opacity="0.85"/>"##
        case 3:
            return base + ##"<g clip-path="url(#body)"><rect x="20" y="178" width="160" height="9" fill="#FFFFFF" opacity="0.9"/><rect x="20" y="190" width="160" height="5" fill="\##(dark)"/></g><path d="M82 148 Q100 168 118 148" fill="none" stroke="#FFFFFF" stroke-width="5" stroke-linecap="round"/>"##
        case 4:
            return base + ##"<path d="M80 144 L82 164 L100 172 L118 164 L120 144 Q100 164 80 144 Z" fill="#F5C542"/><path d="M100 172 L100 200" stroke="#F5C542" stroke-width="3"/><circle cx="100" cy="182" r="3.4" fill="#F5C542"/><circle cx="100" cy="194" r="3.4" fill="#F5C542"/><path d="M34 190 C34 176 44 164 58 158" stroke="#F5C542" stroke-width="3" fill="none"/>"##
        case 5:
            return base + ##"<path d="M34 196 C38 164 68 152 82 150 L108 156 C138 166 160 184 168 200 L140 200 C130 182 104 174 74 178 Z" fill="\##(light)"/><path d="M34 196 C38 164 68 152 82 150 L108 156 C138 166 160 184 168 200" fill="none" stroke="#F5C542" stroke-width="3"/>"##
        default:
            return base
        }
    }

    private static func ears(_ s: AvatarSpec, skin: String, shade: String) -> String {
        let (lx, rx, y): (Int, Int, Int) = s.face == 2 ? (54, 146, 98) : (52, 148, 98)
        var t = ##"<ellipse cx="\##(lx)" cy="\##(y)" rx="7" ry="11" fill="\##(skin)"/><ellipse cx="\##(rx)" cy="\##(y)" rx="7" ry="11" fill="\##(skin)"/>"##
        t += ##"<ellipse cx="\##(lx)" cy="\##(y)" rx="3" ry="6" fill="\##(shade)" opacity="0.6"/><ellipse cx="\##(rx)" cy="\##(y)" rx="3" ry="6" fill="\##(shade)" opacity="0.6"/>"##
        if s.has(.earrings) {
            t += ##"<circle cx="\##(lx)" cy="\##(y + 13)" r="3.6" fill="#F5C542"/><path d="M\##(lx) \##(y + 16) l-3 8 h6 Z" fill="#F5C542"/>"##
            t += ##"<circle cx="\##(rx)" cy="\##(y + 13)" r="3.6" fill="#F5C542"/><path d="M\##(rx) \##(y + 16) l-3 8 h6 Z" fill="#F5C542"/>"##
        }
        return t
    }

    private static func head(_ s: AvatarSpec, skin: String) -> String {
        switch s.face {
        case 1: ##"<ellipse cx="100" cy="94" rx="42" ry="56" fill="\##(skin)"/>"##
        case 2: ##"<rect x="54" y="42" width="92" height="104" rx="38" fill="\##(skin)"/>"##
        default: ##"<ellipse cx="100" cy="94" rx="47" ry="51" fill="\##(skin)"/>"##
        }
    }

    private static func face(_ s: AvatarSpec, hair: String, hairDark: String, shade: String) -> String {
        var t = ""
        if s.has(.blush) {
            t += ##"<circle cx="68" cy="112" r="8" fill="#FF6B6B" opacity="0.28"/><circle cx="132" cy="112" r="8" fill="#FF6B6B" opacity="0.28"/>"##
        }
        if s.has(.bindi) { t += ##"<circle cx="100" cy="72" r="3.4" fill="#D61F3A"/>"## }
        t += ##"<path d="M100 100 Q95 112 98 114 Q102 116 106 113" fill="none" stroke="\##(shade)" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>"##
        t += brows(s, color: hairDark)
        t += eyes(s)
        if s.facialHair == 3 { t += beardBack(hair) }
        t += mouth(s)
        t += facialHair(s, hair: hair)
        return t
    }

    private static func brows(_ s: AvatarSpec, color: String) -> String {
        let d: String
        switch s.brows {
        case 1: d = "M70 84 Q80 75 90 82"
        case 2: d = "M69 80 L90 85"
        default: d = "M70 82 L90 80"
        }
        return ##"<g fill="none" stroke="\##(color)" stroke-width="4.2" stroke-linecap="round"><path d="\##(d)"/><g transform="translate(200 0) scale(-1 1)"><path d="\##(d)"/></g></g>"##
    }

    private static func eyes(_ s: AvatarSpec) -> String {
        func dot(_ x: Int) -> String {
            ##"<circle cx="\##(x)" cy="96" r="4.6" fill="#1F1B24"/><circle cx="\##(Double(x) + 1.6)" cy="94.2" r="1.5" fill="#FFFFFF"/>"##
        }
        func almond(_ x: Int) -> String {
            ##"<ellipse cx="\##(x)" cy="96" rx="8.5" ry="5.8" fill="#FFFFFF"/><circle cx="\##(x)" cy="96" r="4.2" fill="#3A2A20"/><circle cx="\##(x)" cy="96" r="2" fill="#0B0B0F"/><circle cx="\##(Double(x) + 1.4)" cy="94.4" r="1.3" fill="#FFFFFF"/>"##
        }
        func happy(_ x: Int) -> String {
            ##"<path d="M\##(x - 8) 98 Q\##(x) 87 \##(x + 8) 98" fill="none" stroke="#1F1B24" stroke-width="3.6" stroke-linecap="round"/>"##
        }
        func sleepy(_ x: Int) -> String {
            ##"<path d="M\##(x - 8) 95 Q\##(x) 101 \##(x + 8) 95" fill="none" stroke="#1F1B24" stroke-width="3.6" stroke-linecap="round"/>"##
        }
        switch s.eyes {
        case 1: return almond(80) + almond(120)
        case 2: return happy(80) + happy(120)
        case 3: return sleepy(80) + sleepy(120)
        case 4: return dot(80) + happy(120)
        default: return dot(80) + dot(120)
        }
    }

    private static func mouth(_ s: AvatarSpec) -> String {
        let ink = "#7A2E34"
        switch s.mouth {
        case 1:
            return ##"<path d="M82 120 Q100 142 118 120 Z" fill="\##(ink)"/><path d="M86 121 Q100 127 114 121 Q100 131 86 121 Z" fill="#FFFFFF"/>"##
        case 2: return ##"<path d="M86 126 Q102 132 117 120" fill="none" stroke="\##(ink)" stroke-width="3.6" stroke-linecap="round"/>"##
        case 3: return ##"<path d="M88 126 L112 126" fill="none" stroke="\##(ink)" stroke-width="3.6" stroke-linecap="round"/>"##
        case 4: return ##"<ellipse cx="100" cy="128" rx="7" ry="8.5" fill="\##(ink)"/><ellipse cx="100" cy="132" rx="4.4" ry="3" fill="#E36A78"/>"##
        default: return ##"<path d="M84 121 Q100 137 116 121" fill="none" stroke="\##(ink)" stroke-width="3.6" stroke-linecap="round"/>"##
        }
    }

    private static func beardBack(_ hair: String) -> String {
        ##"<path d="M53 100 C50 150 78 162 100 162 C122 162 150 150 147 100 C141 126 124 134 100 134 C76 134 59 126 53 100 Z" fill="\##(hair)"/>"##
    }

    private static func facialHair(_ s: AvatarSpec, hair: String) -> String {
        switch s.facialHair {
        case 1, 3:
            return ##"<path d="M100 117 C92 110 79 112 72 119 C80 123 89 122 100 120 C111 122 120 123 128 119 C121 112 108 110 100 117 Z" fill="\##(hair)"/>"##
        case 2:
            return ##"<path d="M55 100 Q58 148 100 150 Q142 148 145 100 Q132 130 100 130 Q68 130 55 100 Z" fill="\##(hair)" opacity="0.3"/>"##
        case 4:
            return ##"<path d="M100 117 C92 111 80 113 74 119 C82 122 90 121 100 119 C110 121 118 122 126 119 C120 113 108 111 100 117 Z" fill="\##(hair)"/><path d="M89 137 Q100 156 111 137 Q100 142 89 137 Z" fill="\##(hair)"/>"##
        default: return ""
        }
    }

    private static func hairFront(_ s: AvatarSpec, hair: String, dark: String) -> String {
        switch s.hair {
        case 1:
            return ##"<path d="M53 90 C47 48 76 34 100 34 C126 34 153 48 147 90 C141 68 124 60 100 60 C76 60 59 68 53 90 Z" fill="\##(hair)"/>"##
        case 2:
            return ##"<path d="M51 94 C42 48 80 28 108 34 C140 40 156 64 149 94 C146 74 134 64 116 58 C102 72 72 74 58 84 Z" fill="\##(hair)"/><path d="M116 58 C124 44 108 36 100 38" fill="none" stroke="\##(dark)" stroke-width="3" stroke-linecap="round" opacity="0.6"/>"##
        case 3:
            var t = ""
            for i in 0 ..< 8 {
                let a = (200.0 + Double(i) * 20.0) * .pi / 180
                t += String(format: ##"<circle cx="%.1f" cy="%.1f" r="15" fill="%@"/>"##, 100 + 52 * cos(a), 84 + 50 * sin(a), hair)
            }
            return t + ##"<path d="M56 86 C60 66 80 58 100 58 C120 58 140 66 144 86 C136 74 120 68 100 68 C80 68 64 74 56 86 Z" fill="\##(hair)"/>"##
        case 4:
            return ##"<path d="M50 96 C42 46 82 28 108 34 C140 38 158 64 150 96 C148 76 136 62 118 56 C98 72 70 72 56 84 Z" fill="\##(hair)"/>"##
        case 5:
            return ##"<path d="M53 90 C47 48 76 34 100 34 C126 34 153 48 147 90 C141 68 124 60 100 60 C76 60 59 68 53 90 Z" fill="\##(hair)"/><circle cx="100" cy="26" r="15" fill="\##(hair)"/><rect x="90" y="34" width="20" height="8" rx="3" fill="\##(dark)"/>"##
        case 6:
            return ##"<path d="M56 84 C54 54 78 44 100 44 C122 44 146 54 144 84 C136 64 120 58 100 58 C80 58 64 64 56 84 Z" fill="\##(hair)" opacity="0.75"/>"##
        case 7:
            return ##"<path d="M55 86 C58 64 80 54 100 54 C120 54 142 64 145 86 C136 70 120 64 100 64 C80 64 64 70 55 86 Z" fill="\##(hair)"/>"##
        default: return ""
        }
    }

    private static func headwear(_ s: AvatarSpec, cloth: String, dark: String, light: String) -> String {
        switch s.headwear {
        case 1: // pagdi
            return ##"<path d="M48 84 C42 32 76 12 100 12 C126 12 158 32 152 84 C142 64 122 56 100 56 C78 56 58 64 48 84 Z" fill="\##(cloth)"/><path d="M52 70 C74 50 126 50 148 70" fill="none" stroke="\##(dark)" stroke-width="3" opacity="0.7"/><path d="M50 58 C72 36 128 36 150 58" fill="none" stroke="\##(light)" stroke-width="3" opacity="0.7"/><path d="M56 44 C76 26 124 26 144 44" fill="none" stroke="\##(dark)" stroke-width="3" opacity="0.6"/><path d="M92 58 L100 46 L108 58 L100 66 Z" fill="#F5C542"/><circle cx="100" cy="57" r="2.6" fill="#D61F3A"/>"##
        case 2: // topi
            return ##"<path d="M50 80 C50 52 76 38 100 42 C124 38 150 52 150 80 C130 70 70 70 50 80 Z" fill="#F4F1E8"/><path d="M50 80 C70 70 130 70 150 80 L150 86 C130 77 70 77 50 86 Z" fill="#D9D4C3"/><path d="M100 42 L100 71" stroke="#D9D4C3" stroke-width="2"/>"##
        case 3: // beanie
            return ##"<path d="M50 78 C46 38 76 24 100 24 C124 24 154 38 150 78 Z" fill="\##(cloth)"/><rect x="46" y="68" width="108" height="16" rx="8" fill="\##(dark)"/><circle cx="100" cy="20" r="9" fill="\##(light)"/>"##
        case 4: // cap
            return ##"<path d="M52 78 C48 40 76 28 100 28 C124 28 152 40 148 78 Z" fill="\##(cloth)"/><path d="M100 28 L100 76" stroke="\##(dark)" stroke-width="2" opacity="0.6"/><path d="M52 78 C80 70 120 70 148 78 L172 84 C150 90 100 82 52 84 Z" fill="\##(dark)"/>"##
        default: return ""
        }
    }

    private static func glasses(_ s: AvatarSpec) -> String {
        switch s.glasses {
        case 1:
            return ##"<g fill="#FFFFFF" fill-opacity="0.18" stroke="#2A2630" stroke-width="3"><circle cx="80" cy="96" r="14"/><circle cx="120" cy="96" r="14"/><path d="M94 94 Q100 90 106 94" fill="none"/><path d="M66 94 L54 90 M134 94 L146 90" fill="none"/></g>"##
        case 2:
            return ##"<g fill="#FFFFFF" fill-opacity="0.18" stroke="#2A2630" stroke-width="3"><rect x="65" y="84" width="30" height="24" rx="6"/><rect x="105" y="84" width="30" height="24" rx="6"/><path d="M95 93 L105 93" fill="none"/><path d="M65 92 L54 89 M135 92 L146 89" fill="none"/></g>"##
        case 3:
            return ##"<g fill="#15131A" stroke="#15131A" stroke-width="3"><path d="M64 86 H96 V98 Q96 110 80 110 Q64 110 64 98 Z"/><path d="M104 86 H136 V98 Q136 110 120 110 Q104 110 104 98 Z"/><path d="M96 90 L104 90" fill="none"/><path d="M64 90 L54 88 M136 90 L146 88" fill="none"/></g><path d="M69 91 L80 91 L72 101 Z M109 91 L120 91 L112 101 Z" fill="#FFFFFF" opacity="0.25"/>"##
        default: return ""
        }
    }
}
