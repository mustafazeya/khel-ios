import Foundation

/// The whole look of an avatar as a handful of small integers. Codable and tiny, so it is saved in the profile
/// and sent to other players when they join a room; every device draws the same face from it.
struct AvatarSpec: Codable, Hashable, Sendable {
    var skin = 2
    var face = 0
    var hair = 1
    var hairColor = 0
    var brows = 0
    var eyes = 0
    var mouth = 0
    var facialHair = 0
    var headwear = 0
    var glasses = 0
    var clothing = 0
    var clothingColor = 0
    var background = 0
    var backgroundColor = 0
    /// Bit 0 bindi, bit 1 earrings, bit 2 blush.
    var extras = 0

    enum Extra: Int { case bindi = 1, earrings = 2, blush = 4 }

    func has(_ e: Extra) -> Bool { extras & e.rawValue != 0 }
    mutating func set(_ e: Extra, _ on: Bool) { if on { extras |= e.rawValue } else { extras &= ~e.rawValue } }

    // Option counts, shared by the generator, the randomiser and the editor.
    static let skinTones = ["#FBE3D0", "#F4C9A5", "#E2A678", "#C68B5B", "#A56A40", "#7A4A2A", "#55331F"]
    static let hairColors = ["#17171B", "#33201A", "#5C3A21", "#8A4B2A", "#8E8E96", "#EDEDED", "#D6AE62", "#14B8A6", "#EC4899", "#6366F1"]
    static let clothingColors = ["#EF4444", "#F97316", "#EAB308", "#22C55E", "#06B6D4", "#3B82F6", "#8B5CF6", "#EC4899", "#14B8A6", "#F5F5F4"]
    static let backgroundPairs: [(String, String)] = [
        ("#FF9A3C", "#FF4E7A"), ("#38BDF8", "#6366F1"), ("#34D399", "#0EA5A4"), ("#F472B6", "#A855F7"),
        ("#FACC15", "#FB923C"), ("#2DD4BF", "#3B82F6"), ("#94A3B8", "#475569"), ("#FB7185", "#F59E0B"),
    ]

    static let faceCount = 3, hairCount = 8, browCount = 3, eyeCount = 5, mouthCount = 5, facialHairCount = 5
    static let headwearCount = 5, glassesCount = 4, clothingCount = 6, backgroundCount = 4

    static let faceNames = ["Round", "Oval", "Square"]
    static let hairNames = ["Bald", "Crop", "Side part", "Curly", "Long", "Bun", "Buzz", "Afro"]
    static let eyeNames = ["Dots", "Almond", "Happy", "Sleepy", "Wink"]
    static let mouthNames = ["Smile", "Grin", "Smirk", "Calm", "Wow"]
    static let facialHairNames = ["None", "Mustache", "Stubble", "Beard", "Goatee"]
    static let headwearNames = ["None", "Pagdi", "Topi", "Beanie", "Cap"]
    static let glassesNames = ["None", "Round", "Square", "Shades"]
    static let clothingNames = ["Tee", "Kurta", "Hoodie", "Jersey", "Sherwani", "Dupatta"]

    /// A pleasant random avatar; the same seed always gives the same face.
    static func random(seed: UInt64) -> AvatarSpec {
        var r = SplitMix64(seed: seed)
        var s = AvatarSpec()
        s.skin = r.int(in: 0 ... skinTones.count - 1)
        s.face = r.int(in: 0 ... faceCount - 1)
        s.hair = r.int(in: 0 ... hairCount - 1)
        s.hairColor = r.int(in: 0 ... 6)
        s.brows = r.int(in: 0 ... browCount - 1)
        s.eyes = r.int(in: 0 ... eyeCount - 1)
        s.mouth = r.int(in: 0 ... mouthCount - 1)
        s.facialHair = r.int(in: 0 ... 9) < 6 ? 0 : r.int(in: 1 ... facialHairCount - 1)
        s.headwear = r.int(in: 0 ... 9) < 7 ? 0 : r.int(in: 1 ... headwearCount - 1)
        s.glasses = r.int(in: 0 ... 9) < 7 ? 0 : r.int(in: 1 ... glassesCount - 1)
        s.clothing = r.int(in: 0 ... clothingCount - 1)
        s.clothingColor = r.int(in: 0 ... clothingColors.count - 1)
        s.background = r.int(in: 0 ... backgroundCount - 1)
        s.backgroundColor = r.int(in: 0 ... backgroundPairs.count - 1)
        s.extras = r.int(in: 0 ... 7)
        return s.clamped
    }

    /// Every field forced into its valid range, so data from an older or newer app version can never crash the renderer.
    var clamped: AvatarSpec {
        func c(_ v: Int, _ n: Int) -> Int { min(max(v, 0), n - 1) }
        var s = self
        s.skin = c(skin, Self.skinTones.count); s.face = c(face, Self.faceCount); s.hair = c(hair, Self.hairCount)
        s.hairColor = c(hairColor, Self.hairColors.count); s.brows = c(brows, Self.browCount); s.eyes = c(eyes, Self.eyeCount)
        s.mouth = c(mouth, Self.mouthCount); s.facialHair = c(facialHair, Self.facialHairCount)
        s.headwear = c(headwear, Self.headwearCount); s.glasses = c(glasses, Self.glassesCount)
        s.clothing = c(clothing, Self.clothingCount); s.clothingColor = c(clothingColor, Self.clothingColors.count)
        s.background = c(background, Self.backgroundCount); s.backgroundColor = c(backgroundColor, Self.backgroundPairs.count)
        s.extras = extras & 7
        return s
    }
}
