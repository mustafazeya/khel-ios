import Foundation

struct ChessMove: Codable, Equatable, Sendable, Hashable {
    var from: Int
    var to: Int
    /// 0, or the piece type a pawn promotes to (2 knight, 3 bishop, 4 rook, 5 queen).
    var promo: Int = 0
}

/// Board position. Squares 0...63 with a8 = 0 and h1 = 63. Pieces are signed: +1...+6 white, -1...-6 black
/// (pawn, knight, bishop, rook, queen, king).
struct ChessPosition: Codable, Equatable, Sendable {
    var b: [Int8]
    var side = 1
    /// Bits: 1 white king side, 2 white queen side, 4 black king side, 8 black queen side.
    var castle = 15
    var ep = -1
    var half = 0
    var full = 1
    var kings = [60, 4]

    struct Undo {
        var move: ChessMove
        var moved: Int8
        var captured: Int8
        var capSq: Int
        var castle: Int
        var ep: Int
        var half: Int
    }

    static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    static let start = ChessPosition(fen: startFEN)!

    init?(fen: String) {
        let parts = fen.split(separator: " ").map(String.init)
        guard parts.count >= 2 else { return nil }
        var board = [Int8](repeating: 0, count: 64)
        var kings = [-1, -1]
        var sq = 0
        for ch in parts[0] {
            if ch == "/" { continue }
            if let n = ch.wholeNumberValue { sq += n; continue }
            let type: Int8
            switch ch.lowercased() {
            case "p": type = 1; case "n": type = 2; case "b": type = 3; case "r": type = 4; case "q": type = 5; case "k": type = 6
            default: return nil
            }
            guard sq < 64 else { return nil }
            board[sq] = ch.isUppercase ? type : -type
            if type == 6 { kings[ch.isUppercase ? 0 : 1] = sq }
            sq += 1
        }
        guard sq == 64, kings[0] >= 0, kings[1] >= 0 else { return nil }
        b = board
        self.kings = kings
        side = parts[1] == "b" ? -1 : 1
        castle = 0
        if parts.count > 2 { for c in parts[2] { switch c { case "K": castle |= 1; case "Q": castle |= 2; case "k": castle |= 4; case "q": castle |= 8; default: break } } }
        if parts.count > 3, parts[3] != "-", parts[3].count == 2 {
            let f = Int(parts[3].unicodeScalars.first!.value) - 97, r = 8 - (Int(String(parts[3].last!)) ?? 0)
            ep = (0 ..< 8).contains(f) && (0 ..< 8).contains(r) ? r * 8 + f : -1
        }
        if parts.count > 4 { half = Int(parts[4]) ?? 0 }
        if parts.count > 5 { full = Int(parts[5]) ?? 1 }
    }

    private static let knightD = [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)]
    private static let kingD = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
    private static let bishopD = [(-1, -1), (-1, 1), (1, -1), (1, 1)]
    private static let rookD = [(-1, 0), (1, 0), (0, -1), (0, 1)]

    // MARK: Attacks

    func isAttacked(_ sq: Int, by color: Int) -> Bool {
        let r = sq / 8, c = sq % 8
        let col8 = Int8(color)
        let pr = r + color
        if (0 ..< 8).contains(pr) {
            if c > 0, b[pr * 8 + c - 1] == col8 { return true }
            if c < 7, b[pr * 8 + c + 1] == col8 { return true }
        }
        for (dr, dc) in Self.knightD {
            let rr = r + dr, cc = c + dc
            if (0 ..< 8).contains(rr), (0 ..< 8).contains(cc), b[rr * 8 + cc] == 2 * col8 { return true }
        }
        for (dr, dc) in Self.kingD {
            let rr = r + dr, cc = c + dc
            if (0 ..< 8).contains(rr), (0 ..< 8).contains(cc), b[rr * 8 + cc] == 6 * col8 { return true }
        }
        for (dr, dc) in Self.bishopD {
            var rr = r + dr, cc = c + dc
            while (0 ..< 8).contains(rr), (0 ..< 8).contains(cc) {
                let p = b[rr * 8 + cc]
                if p != 0 { if p == 3 * col8 || p == 5 * col8 { return true }; break }
                rr += dr; cc += dc
            }
        }
        for (dr, dc) in Self.rookD {
            var rr = r + dr, cc = c + dc
            while (0 ..< 8).contains(rr), (0 ..< 8).contains(cc) {
                let p = b[rr * 8 + cc]
                if p != 0 { if p == 4 * col8 || p == 5 * col8 { return true }; break }
                rr += dr; cc += dc
            }
        }
        return false
    }

    var inCheck: Bool { isAttacked(kings[side == 1 ? 0 : 1], by: -side) }

    // MARK: Move generation

    /// Pseudo-legal moves (king safety not yet checked). With `capturesOnly`, captures and promotions only.
    func pseudoMoves(capturesOnly: Bool = false) -> [ChessMove] {
        var out: [ChessMove] = []
        out.reserveCapacity(48)
        let s = Int8(side)
        for from in 0 ..< 64 {
            let p = b[from]
            guard p != 0, (p > 0) == (side == 1) else { continue }
            let r = from / 8, c = from % 8
            switch abs(p) {
            case 1:
                let dir = -side, fr = r + dir
                guard (0 ..< 8).contains(fr) else { continue }
                let promoRow = side == 1 ? 0 : 7
                func add(_ to: Int) {
                    if fr == promoRow { for pr in [5, 4, 3, 2] { out.append(ChessMove(from: from, to: to, promo: pr)) } }
                    else { out.append(ChessMove(from: from, to: to)) }
                }
                if b[fr * 8 + c] == 0 {
                    if !capturesOnly || fr == promoRow {
                        add(fr * 8 + c)
                    }
                    if !capturesOnly, r == (side == 1 ? 6 : 1), b[(r + 2 * dir) * 8 + c] == 0 { out.append(ChessMove(from: from, to: (r + 2 * dir) * 8 + c)) }
                }
                for dc in [-1, 1] {
                    let cc = c + dc
                    guard (0 ..< 8).contains(cc) else { continue }
                    let t = b[fr * 8 + cc]
                    if t != 0 { if (t > 0) != (side == 1) { add(fr * 8 + cc) } }
                    else if fr * 8 + cc == ep { out.append(ChessMove(from: from, to: ep)) }
                }
            case 2, 6:
                let dirs = abs(p) == 2 ? Self.knightD : Self.kingD
                for (dr, dc) in dirs {
                    let rr = r + dr, cc = c + dc
                    guard (0 ..< 8).contains(rr), (0 ..< 8).contains(cc) else { continue }
                    let t = b[rr * 8 + cc]
                    if t == 0 { if !capturesOnly { out.append(ChessMove(from: from, to: rr * 8 + cc)) } }
                    else if (t > 0) != (side == 1) { out.append(ChessMove(from: from, to: rr * 8 + cc)) }
                }
                if abs(p) == 6, !capturesOnly { castling(from: from, into: &out) }
            default:
                var dirs: [(Int, Int)] = []
                if abs(p) != 4 { dirs += Self.bishopD }
                if abs(p) != 3 { dirs += Self.rookD }
                for (dr, dc) in dirs {
                    var rr = r + dr, cc = c + dc
                    while (0 ..< 8).contains(rr), (0 ..< 8).contains(cc) {
                        let t = b[rr * 8 + cc]
                        if t == 0 { if !capturesOnly { out.append(ChessMove(from: from, to: rr * 8 + cc)) } }
                        else { if (t > 0) != (side == 1) { out.append(ChessMove(from: from, to: rr * 8 + cc)) }; break }
                        rr += dr; cc += dc
                    }
                }
            }
        }
        _ = s
        return out
    }

    private func castling(from: Int, into out: inout [ChessMove]) {
        if side == 1, from == 60 {
            if castle & 1 != 0, b[61] == 0, b[62] == 0, b[63] == 4, !isAttacked(60, by: -1), !isAttacked(61, by: -1) { out.append(ChessMove(from: 60, to: 62)) }
            if castle & 2 != 0, b[59] == 0, b[58] == 0, b[57] == 0, b[56] == 4, !isAttacked(60, by: -1), !isAttacked(59, by: -1) { out.append(ChessMove(from: 60, to: 58)) }
        } else if side == -1, from == 4 {
            if castle & 4 != 0, b[5] == 0, b[6] == 0, b[7] == -4, !isAttacked(4, by: 1), !isAttacked(5, by: 1) { out.append(ChessMove(from: 4, to: 6)) }
            if castle & 8 != 0, b[3] == 0, b[2] == 0, b[1] == 0, b[0] == -4, !isAttacked(4, by: 1), !isAttacked(3, by: 1) { out.append(ChessMove(from: 4, to: 2)) }
        }
    }

    // MARK: Make / unmake

    @discardableResult
    mutating func make(_ m: ChessMove) -> Undo {
        let piece = b[m.from]
        var captured = b[m.to]
        var capSq = m.to
        let undo = Undo(move: m, moved: piece, captured: 0, capSq: m.to, castle: castle, ep: ep, half: half)
        if abs(piece) == 1, m.to == ep, captured == 0, m.from % 8 != m.to % 8 {
            capSq = m.from / 8 * 8 + m.to % 8
            captured = b[capSq]
            b[capSq] = 0
        }
        b[m.to] = m.promo != 0 ? Int8(m.promo) * Int8(side) : piece
        b[m.from] = 0
        if abs(piece) == 6 {
            kings[side == 1 ? 0 : 1] = m.to
            if m.to - m.from == 2 { b[m.to - 1] = b[m.to + 1]; b[m.to + 1] = 0 }
            else if m.from - m.to == 2 { b[m.to + 1] = b[m.to - 2]; b[m.to - 2] = 0 }
            castle &= side == 1 ? ~3 : ~12
        }
        for sq in [m.from, m.to] {
            switch sq { case 63: castle &= ~1; case 56: castle &= ~2; case 7: castle &= ~4; case 0: castle &= ~8; default: break }
        }
        ep = abs(piece) == 1 && abs(m.to - m.from) == 16 ? (m.from + m.to) / 2 : -1
        half = abs(piece) == 1 || captured != 0 ? 0 : half + 1
        if side == -1 { full += 1 }
        side = -side
        var u = undo
        u.captured = captured
        u.capSq = capSq
        return u
    }

    mutating func unmake(_ u: Undo) {
        side = -side
        if side == -1 { full -= 1 }
        let m = u.move
        b[m.to] = 0
        b[m.from] = u.moved
        b[u.capSq] = u.captured
        if abs(u.moved) == 6 {
            kings[side == 1 ? 0 : 1] = m.from
            if m.to - m.from == 2 { b[m.to + 1] = b[m.to - 1]; b[m.to - 1] = 0 }
            else if m.from - m.to == 2 { b[m.to - 2] = b[m.to + 1]; b[m.to + 1] = 0 }
        }
        castle = u.castle; ep = u.ep; half = u.half
    }

    /// Moves that do not leave the mover's king in check.
    func legalMoves() -> [ChessMove] {
        var p = self
        var out: [ChessMove] = []
        for m in pseudoMoves() {
            let u = p.make(m)
            if !p.isAttacked(p.kings[side == 1 ? 0 : 1], by: -side) { out.append(m) }
            p.unmake(u)
        }
        return out
    }

    func perft(_ depth: Int) -> Int {
        if depth == 0 { return 1 }
        var p = self
        var n = 0
        for m in p.pseudoMoves() {
            let u = p.make(m)
            if !p.isAttacked(p.kings[-p.side == 1 ? 0 : 1], by: p.side) { n += depth == 1 ? 1 : p.perft(depth - 1) }
            p.unmake(u)
        }
        return n
    }

    // MARK: Draw helpers

    /// A hash for repetition detection: same pieces, side, castling rights and en-passant file.
    func repetitionKey() -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for v in b { h = (h ^ UInt64(UInt8(bitPattern: v))) &* 1099511628211 }
        h = (h ^ UInt64(side + 1)) &* 1099511628211
        h = (h ^ UInt64(castle)) &* 1099511628211
        var epKey = -1
        if ep >= 0 {
            let r = ep / 8, c = ep % 8, pr = r + (side == 1 ? 1 : -1)
            for dc in [-1, 1] where (0 ..< 8).contains(c + dc) && (0 ..< 8).contains(pr) && b[pr * 8 + c + dc] == Int8(side) { epKey = c }
        }
        return (h ^ UInt64(epKey + 1)) &* 1099511628211
    }

    var insufficientMaterial: Bool {
        var minors: [(Int8, Int)] = []
        for (i, p) in b.enumerated() where p != 0 {
            switch abs(p) {
            case 6: continue
            case 2, 3: minors.append((p, i))
            default: return false
            }
        }
        if minors.count <= 1 { return true }
        if minors.count == 2, minors.allSatisfy({ abs($0.0) == 3 }), minors[0].0 != minors[1].0 {
            let color = { (i: Int) in (i / 8 + i % 8) % 2 }
            return color(minors[0].1) == color(minors[1].1)
        }
        return false
    }
}
