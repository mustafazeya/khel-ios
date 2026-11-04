import SwiftUI

// MARK: - Physics

/// A carrom piece. Board units: the playing surface is the unit square, pockets sit in the four corners.
struct CarromPiece: Codable, Equatable, Sendable, Identifiable {
    enum Kind: Int, Codable, Sendable { case white, black, queen, striker }
    var id: Int
    var kind: Kind
    var p: SIMD2<Double>
    var v = SIMD2<Double>(0, 0)
    var pocketed = false

    var radius: Double { kind == .striker ? CarromWorld.strikerR : CarromWorld.coinR }
    var mass: Double { kind == .striker ? 1.7 : 1.0 }
}

/// Deterministic fixed-step simulation. Every device replays the same shot from the same state and gets the same result.
struct CarromWorld: Sendable {
    static let coinR = 0.024, strikerR = 0.03, pocketR = 0.062
    static let dt = 1.0 / 240
    static let maxShotSpeed = 3.4
    static let corners = [SIMD2(0.0, 0.0), SIMD2(1.0, 0.0), SIMD2(0.0, 1.0), SIMD2(1.0, 1.0)]

    var pieces: [CarromPiece]
    var steps = 0

    struct Events: Sendable { var pocketed: [Int] = []; var hits = 0; var walls = 0 }

    var atRest: Bool { pieces.allSatisfy { $0.pocketed || ($0.v.x * $0.v.x + $0.v.y * $0.v.y) < 1e-8 } }

    mutating func step() -> Events {
        var ev = Events()
        let n = pieces.count
        for i in 0 ..< n where !pieces[i].pocketed {
            pieces[i].p += pieces[i].v * Self.dt
            pieces[i].v *= exp(-1.55 * Self.dt)
            let speed = (pieces[i].v.x * pieces[i].v.x + pieces[i].v.y * pieces[i].v.y).squareRoot()
            if speed < 0.035 { pieces[i].v = SIMD2(0, 0) }
        }
        for i in 0 ..< n where !pieces[i].pocketed {
            let r = pieces[i].radius
            // Pockets first, so pieces near a corner are not bounced away from it.
            for c in Self.corners {
                let d = pieces[i].p - c
                if (d.x * d.x + d.y * d.y).squareRoot() < Self.pocketR { pieces[i].pocketed = true; pieces[i].v = SIMD2(0, 0); ev.pocketed.append(pieces[i].id); break }
            }
            if pieces[i].pocketed { continue }
            if pieces[i].p.x < r { pieces[i].p.x = r; pieces[i].v.x = abs(pieces[i].v.x) * 0.82; ev.walls += 1 }
            if pieces[i].p.x > 1 - r { pieces[i].p.x = 1 - r; pieces[i].v.x = -abs(pieces[i].v.x) * 0.82; ev.walls += 1 }
            if pieces[i].p.y < r { pieces[i].p.y = r; pieces[i].v.y = abs(pieces[i].v.y) * 0.82; ev.walls += 1 }
            if pieces[i].p.y > 1 - r { pieces[i].p.y = 1 - r; pieces[i].v.y = -abs(pieces[i].v.y) * 0.82; ev.walls += 1 }
        }
        for i in 0 ..< n where !pieces[i].pocketed {
            for j in (i + 1) ..< n where !pieces[j].pocketed {
                let d = pieces[j].p - pieces[i].p
                let minD = pieces[i].radius + pieces[j].radius
                let dd = d.x * d.x + d.y * d.y
                guard dd < minD * minD else { continue }
                let dist = dd.squareRoot()
                let nrm = dist > 1e-9 ? d / dist : SIMD2(1, 0)
                let mi = pieces[i].mass, mj = pieces[j].mass
                let overlap = minD - dist
                pieces[i].p -= nrm * overlap * (mj / (mi + mj))
                pieces[j].p += nrm * overlap * (mi / (mi + mj))
                let rel = pieces[j].v - pieces[i].v
                let vn = rel.x * nrm.x + rel.y * nrm.y
                if vn < 0 {
                    let impulse = -(1 + 0.93) * vn / (1 / mi + 1 / mj)
                    pieces[i].v -= nrm * (impulse / mi)
                    pieces[j].v += nrm * (impulse / mj)
                    ev.hits += 1
                }
            }
        }
        steps += 1
        return ev
    }

    /// Runs until everything stops (or a safety limit) and returns what was pocketed.
    mutating func simulateToRest(maxSeconds: Double = 8) -> Events {
        var total = Events()
        var quiet = 0
        for _ in 0 ..< Int(maxSeconds / Self.dt) {
            let e = step()
            total.pocketed += e.pocketed; total.hits += e.hits; total.walls += e.walls
            quiet = atRest ? quiet + 1 : 0
            if quiet >= 6 { break }
        }
        for i in pieces.indices { pieces[i].v = SIMD2(0, 0) }
        return total
    }
}

// MARK: - Rules

struct CarromShot: Codable, Equatable, Sendable {
    var number: Int
    var seat: Int
    var x: Double
    var vx: Double
    var vy: Double
}

struct CarromGame: Codable, Equatable, Sendable {
    var pieces: [CarromPiece]
    var turn = 0
    var score = [0, 0]
    /// 0 on the board, 1 pocketed and waiting to be covered, 2 owned by `queenOwner`.
    var queenState = 0
    var queenOwner = -1
    var coverSeat = -1
    var shotNumber = 0
    var over = false
    var winner: Int?
    var message = ""

    static let strikerID = 99
    static func baselineY(_ seat: Int) -> Double { seat == 0 ? 0.845 : 0.155 }
    static let baselineRange = 0.17 ... 0.83

    init() { pieces = Self.initialPieces() }

    static func initialPieces() -> [CarromPiece] {
        let r = CarromWorld.coinR, gap = 0.0015
        var out = [CarromPiece(id: 0, kind: .queen, p: SIMD2(0.5, 0.5))]
        var white = 1, black = 10
        func add(_ k: Int, _ angle: Double, _ rad: Double, even: Bool) {
            let p = SIMD2(0.5 + cos(angle) * rad, 0.5 + sin(angle) * rad)
            if even { out.append(CarromPiece(id: white, kind: .white, p: p)); white += 1 } else { out.append(CarromPiece(id: black, kind: .black, p: p)); black += 1 }
        }
        for k in 0 ..< 6 { add(k, Double(k) * .pi / 3 + .pi / 6, 2 * r + gap, even: k % 2 == 0) }
        for k in 0 ..< 12 { add(k, Double(k) * .pi / 6 + .pi / 6, k % 2 == 0 ? 4 * r + 2 * gap : 2 * 3.0.squareRoot() * r + 2 * gap, even: k % 2 == 0) }
        return out
    }

    func color(of seat: Int) -> CarromPiece.Kind { seat == 0 ? .white : .black }
    func remaining(_ k: CarromPiece.Kind) -> Int { pieces.filter { $0.kind == k && !$0.pocketed }.count }
    func pocketedCount(_ k: CarromPiece.Kind) -> Int { pieces.filter { $0.kind == k && $0.pocketed }.count }

    /// A free spot for a returned piece, as near the centre as possible.
    private func freeSpot() -> SIMD2<Double> {
        let rings: [(Double, Int)] = [(0, 1), (0.06, 6), (0.12, 12), (0.18, 16)]
        for (rad, n) in rings { for k in 0 ..< n {
            let a = Double(k) / Double(n) * .pi * 2
            let c = SIMD2(0.5 + cos(a) * rad, 0.5 + sin(a) * rad)
            if pieces.allSatisfy({ $0.pocketed || ($0.p - c).magnitude > CarromWorld.coinR * 2.1 }) { return c }
        } }
        return SIMD2(0.5, 0.5)
    }

    private mutating func putBack(_ id: Int) {
        guard let i = pieces.firstIndex(where: { $0.id == id }) else { return }
        pieces[i].pocketed = false
        pieces[i].p = SIMD2(100, 100)      // out of the way while looking for a free spot
        pieces[i].p = freeSpot()
        pieces[i].v = SIMD2(0, 0)
    }

    /// Applies the rules for a finished shot. `pocketedIDs` are the ids that went in (already marked in `pieces`).
    mutating func resolve(pocketedIDs: [Int], strikerPocketed: Bool) {
        shotNumber += 1
        let seat = turn
        let mine = color(of: seat), theirs = color(of: 1 - seat)
        let now = pieces.filter { pocketedIDs.contains($0.id) }
        let own = now.filter { $0.kind == mine }.count
        let opp = now.filter { $0.kind == theirs }.count
        let queenNow = now.contains { $0.kind == .queen }
        var extra = false
        message = ""

        if queenState == 1, coverSeat == seat {
            if own > 0 && !strikerPocketed { queenState = 2; queenOwner = seat; score[seat] += 3; message = "Queen covered! +3" }
            else { putBack(0); queenState = 0; coverSeat = -1; message = "Queen not covered: back to the centre" }
        }

        if strikerPocketed {
            message = "Foul: striker pocketed"
            for p in now where p.kind != .striker { putBack(p.id) }
            if let owed = pieces.first(where: { $0.kind == mine && $0.pocketed }) { putBack(owed.id); score[seat] = max(0, score[seat] - 1) }
        } else {
            score[seat] += own
            score[1 - seat] += opp
            extra = own > 0
            if queenNow, queenState == 0 {
                if own > 0 { queenState = 2; queenOwner = seat; score[seat] += 3; message = "Queen and cover! +3" }
                else { queenState = 1; coverSeat = seat; extra = true; message = "Queen down: cover it with your next shot" }
            }
            if own > 0 && message.isEmpty { message = own == 1 ? "Pocketed! Shoot again" : "\(own) pocketed! Shoot again" }
            else if opp > 0 && own == 0 { message = "Pocketed an opponent's piece" }
        }

        if remaining(.white) == 0 || remaining(.black) == 0 {
            over = true
            let cleared = remaining(.white) == 0 ? 0 : 1
            winner = remaining(.white) == 0 && remaining(.black) == 0 ? (score[0] >= score[1] ? 0 : 1) : cleared
            return
        }
        if !extra { turn = 1 - seat }
    }
}

private extension SIMD2 where Scalar == Double {
    var magnitude: Double { (x * x + y * y).squareRoot() }
}

// MARK: - Computer player

enum CarromAI {
    /// Geometric candidates: line the striker up behind a coin so it travels towards a pocket.
    static func candidates(_ g: CarromGame, seat: Int) -> [(shot: CarromShot, score: Double)] {
        let y = CarromGame.baselineY(seat)
        let mineKind = g.color(of: seat)
        var targets = g.pieces.filter { $0.kind == mineKind && !$0.pocketed }
        if g.queenState == 0 || (g.queenState == 1 && g.coverSeat == seat) { targets += g.pieces.filter { $0.kind == .queen && !$0.pocketed } }
        let on = g.pieces.filter { !$0.pocketed }
        var out: [(CarromShot, Double)] = []
        let rc = CarromWorld.coinR, rs = CarromWorld.strikerR

        func clear(from a: SIMD2<Double>, to b: SIMD2<Double>, radius: Double, ignoring: Int) -> Bool {
            let d = b - a
            let len2 = d.x * d.x + d.y * d.y
            for o in on where o.id != ignoring {
                let t = len2 > 0 ? min(1, max(0, ((o.p.x - a.x) * d.x + (o.p.y - a.y) * d.y) / len2)) : 0
                let q = a + d * t
                if (o.p - q).magnitude < radius + rc - 0.003 { return false }
            }
            return true
        }

        for coin in targets {
            for pocket in CarromWorld.corners {
                let toPocket = pocket - coin.p
                let dCP = toPocket.magnitude
                guard dCP > 0.001 else { continue }
                let dirCP = toPocket / dCP
                let ghost = coin.p - dirCP * (rc + rs)
                guard (0.03 ... 0.97).contains(ghost.x), (0.03 ... 0.97).contains(ghost.y) else { continue }
                guard clear(from: coin.p, to: pocket, radius: rc, ignoring: coin.id) else { continue }
                for x in stride(from: CarromGame.baselineRange.lowerBound, through: CarromGame.baselineRange.upperBound, by: 0.055) {
                    let start = SIMD2(x, y)
                    let d = ghost - start
                    let dist = d.magnitude
                    guard dist > 0.02 else { continue }
                    let dirS = d / dist
                    let cut = dirS.x * dirCP.x + dirS.y * dirCP.y
                    guard cut > 0.4 else { continue }
                    guard clear(from: start, to: ghost, radius: rs, ignoring: coin.id) else { continue }
                    let speed = min(CarromWorld.maxShotSpeed, max(1.1, 0.9 + 2.2 * (dist + dCP)))
                    out.append((CarromShot(number: g.shotNumber, seat: seat, x: x, vx: dirS.x * speed, vy: dirS.y * speed), cut * 2 - dist * 0.6 - dCP * 0.9))
                }
            }
        }
        return out.sorted { $0.1 > $1.1 }
    }

    /// Picks a shot. Easy is sloppy, medium is accurate, hard tries its best candidates in a simulation first.
    static func choose(_ g: CarromGame, seat: Int, level: AILevel, seed: UInt64) -> CarromShot {
        var rng = SplitMix64(seed: seed)
        let ranked = candidates(g, seat: seat)
        func jitter(_ s: CarromShot, degrees: Double) -> CarromShot {
            let a = (Double(rng.int(in: -1000 ... 1000)) / 1000) * degrees * .pi / 180
            var t = s
            t.vx = s.vx * cos(a) - s.vy * sin(a); t.vy = s.vx * sin(a) + s.vy * cos(a)
            return t
        }
        guard !ranked.isEmpty else {
            // No clean shot: hit the middle of the board.
            let x = Double(rng.int(in: 30 ... 70)) / 100
            return CarromShot(number: g.shotNumber, seat: seat, x: x, vx: (0.5 - x) * 1.5, vy: seat == 0 ? -2.0 : 2.0)
        }
        switch level {
        case .easy: return jitter(ranked[rng.int(in: 0 ... min(5, ranked.count - 1))].shot, degrees: 7)
        case .medium: return jitter(ranked[0].shot, degrees: 1.8)
        case .hard:
            var best = ranked[0].shot, bestValue = -Double.infinity
            for (shot, _) in ranked.prefix(14) {
                let value = evaluate(g, shot)
                if value > bestValue { bestValue = value; best = shot }
            }
            return jitter(best, degrees: 0.35)
        }
    }

    /// Simulates a shot and values the resulting position for the shooter.
    static func evaluate(_ g: CarromGame, _ shot: CarromShot) -> Double {
        var world = CarromWorld(pieces: g.pieces + [striker(for: shot)])
        let ev = world.simulateToRest(maxSeconds: 5)
        var after = g
        for i in after.pieces.indices {
            if let w = world.pieces.first(where: { $0.id == after.pieces[i].id }) { after.pieces[i].p = w.p; after.pieces[i].pocketed = w.pocketed }
        }
        let strikerIn = ev.pocketed.contains(CarromGame.strikerID)
        after.resolve(pocketedIDs: ev.pocketed.filter { $0 != CarromGame.strikerID }, strikerPocketed: strikerIn)
        var value = Double(after.score[shot.seat] - after.score[1 - shot.seat] - (g.score[shot.seat] - g.score[1 - shot.seat])) * 2
        if after.turn == shot.seat { value += 1.2 }
        if strikerIn { value -= 3 }
        return value
    }

    static func striker(for s: CarromShot) -> CarromPiece {
        CarromPiece(id: CarromGame.strikerID, kind: .striker, p: SIMD2(s.x, CarromGame.baselineY(s.seat)), v: SIMD2(s.vx, s.vy))
    }
}

// MARK: - Model

private enum CarromMessage: Codable {
    case shot(CarromShot)
    case snapshot(CarromGame)
}

@MainActor @Observable
private final class CarromModel {
    enum Phase { case aiming, moving, waiting, over }

    var game = CarromGame()
    var world = CarromWorld(pieces: [])
    var phase = Phase.aiming
    var strikerX = 0.5
    var lastEvent = ""
    private(set) var session: RealtimeSession
    private let level: AILevel
    private var loop: Task<Void, Never>?
    private var pocketedThisShot: [Int] = []
    private var pendingSnapshot: CarromGame?
    private var lastSound = 0.0
    var strikerPosition: SIMD2<Double>? { world.pieces.first { $0.id == CarromGame.strikerID }?.p }

    init(session: RealtimeSession, level: AILevel) {
        self.session = session
        self.level = level
        world = CarromWorld(pieces: game.pieces)
        session.onMessage = { [weak self] data, _ in self?.receive(data) }
        session.onReset = { [weak self] in self?.reset() }
        session.onPeerRejoined = { [weak self] _ in self?.sendSnapshot() }
    }

    var canShoot: Bool { phase == .aiming && session.mySeats.contains(game.turn) && !game.over }

    func start() {
        loop?.cancel()
        updateStatus()
        scheduleAIIfNeeded()
        loop = Task { @MainActor [weak self] in
            var last = ContinuousClock.now
            var acc = 0.0
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(8))
                let now = ContinuousClock.now
                let dt = min(0.05, Double((now - last).components.seconds) + Double((now - last).components.attoseconds) / 1e18)
                last = now
                guard self.phase == .moving else { acc = 0; continue }
                acc += dt
                var hits = 0, walls = 0
                while acc >= CarromWorld.dt, self.phase == .moving {
                    acc -= CarromWorld.dt
                    let e = self.world.step()
                    self.pocketedThisShot += e.pocketed
                    hits += e.hits; walls += e.walls
                    if self.world.atRest { self.shotFinished(); break }
                }
                if hits > 0 { Feedback.shared.thud(); Feedback.shared.play(.tap) } else if walls > 0 { Feedback.shared.play(.place) }
            }
        }
    }

    func stop() { loop?.cancel() }

    func reset() {
        game = CarromGame()
        world = CarromWorld(pieces: game.pieces)
        phase = .aiming; pocketedThisShot = []; pendingSnapshot = nil; strikerX = 0.5
        updateStatus(); scheduleAIIfNeeded()
    }

    // MARK: Shots

    func shoot(vx: Double, vy: Double) {
        guard canShoot else { return }
        let x = CarromGame.baselineRange.lowerBound + strikerX * (CarromGame.baselineRange.upperBound - CarromGame.baselineRange.lowerBound)
        let shot = CarromShot(number: game.shotNumber, seat: game.turn, x: x, vx: vx, vy: vy)
        begin(shot)
        if session.isNetworked { send(.shot(shot)) }
    }

    private func begin(_ shot: CarromShot) {
        pocketedThisShot = []
        world = CarromWorld(pieces: game.pieces.map { var p = $0; p.v = .zero; return p } + [CarromAI.striker(for: shot)])
        phase = .moving
        session.status = ""
    }

    private func shotFinished() {
        let strikerIn = pocketedThisShot.contains(CarromGame.strikerID)
        let coins = pocketedThisShot.filter { $0 != CarromGame.strikerID }
        guard session.isAuthority else {
            phase = .waiting
            if let snap = pendingSnapshot { apply(snap) }
            return
        }
        var g = game
        for w in world.pieces where w.id != CarromGame.strikerID {
            if let i = g.pieces.firstIndex(where: { $0.id == w.id }) { g.pieces[i].p = w.p; g.pieces[i].pocketed = w.pocketed; g.pieces[i].v = .zero }
        }
        g.resolve(pocketedIDs: coins, strikerPocketed: strikerIn)
        apply(g)
        sendSnapshot()
        if g.over, let w = g.winner {
            session.finish(.win(w, others: [1 - w], summary: "\(g.score[w]) – \(g.score[1 - w]) points"))
        }
    }

    private func apply(_ g: CarromGame) {
        let scored = g.score != game.score
        game = g
        world = CarromWorld(pieces: g.pieces)
        pendingSnapshot = nil
        phase = g.over ? .over : .aiming
        if scored { Feedback.shared.success() }
        if !g.message.isEmpty { lastEvent = g.message }
        updateStatus()
        if !g.over { scheduleAIIfNeeded() }
    }

    private func updateStatus() {
        let name = session.seats.indices.contains(game.turn) ? session.seats[game.turn].name : ""
        let mine = session.mySeats.contains(game.turn)
        let base = mine ? (session.mySeats.count > 1 ? "\(name): your shot" : "Your shot") : "\(name) is aiming…"
        session.status = game.over ? "" : (lastEvent.isEmpty ? base : "\(lastEvent) · \(base)")
    }

    // MARK: Network

    private func send(_ m: CarromMessage) { session.send(m) }
    private func sendSnapshot() { if session.isNetworked, session.isAuthority { send(.snapshot(game)) } }

    private func receive(_ data: Data) {
        guard let m = try? JSONDecoder().decode(CarromMessage.self, from: data) else { return }
        switch m {
        case .shot(let s):
            guard phase == .aiming, s.number == game.shotNumber else { return }
            if session.isAuthority { guard s.seat == game.turn, !session.mySeats.contains(s.seat), !session.aiSeats.contains(s.seat) else { return } }
            begin(s)
        case .snapshot(let g):
            if session.isAuthority { return }
            if phase == .moving { pendingSnapshot = g } else { apply(g) }
        }
    }

    // MARK: Computer

    private func scheduleAIIfNeeded() {
        guard session.isAuthority, !game.over, session.aiSeats.contains(game.turn) else { return }
        let g = game, seat = game.turn, level = level
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            let shot = await Task.detached(priority: .userInitiated) { CarromAI.choose(g, seat: seat, level: level, seed: UInt64(g.shotNumber) &* 7919 &+ 3) }.value
            guard let self, self.phase == .aiming, self.game.shotNumber == g.shotNumber, self.game.turn == seat else { return }
            self.begin(shot)
            if self.session.isNetworked { self.send(.shot(shot)) }
        }
    }
}

// MARK: - View

struct CarromView: View {
    static let info = GameInfo(
        id: "carrom", title: "Carrom", tagline: "Flick, pocket, win the queen", symbol: "target", origin: .indian, mode: .realtime,
        minPlayers: 2, maxPlayers: 2, palette: [0xB06A2C, 0xE8B46B], supportsAI: true,
        rules: "Slide the striker along your baseline with the slider, then pull back anywhere on the board and release to shoot. Pocket your own colour (white for the first player, black for the second): each coin scores 1 and gives you another shot. Pocketing the queen scores 3 once you cover it by pocketing one of your own coins, on the same shot or your next one; otherwise it goes back to the centre. Pocketing the striker is a foul: your pocketed coins go back and you lose a point. Clear all your coins to win.")

    let session: RealtimeSession
    @State private var model: CarromModel
    @State private var aim: CGSize?

    init(session: RealtimeSession) {
        self.session = session
        let level = session.launch.seats.compactMap { seat -> AILevel? in if case .ai(let l) = seat.kind { l } else { nil } }.first ?? .medium
        _model = State(initialValue: CarromModel(session: session, level: level))
    }

    private var flipped: Bool { session.mySeats == [1] || (session.mySeats.count > 1 && model.game.turn == 1) }

    var body: some View {
        VStack(spacing: 10) {
            scoreBar
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                ZStack {
                    TimelineView(.animation) { _ in Canvas { ctx, size in draw(&ctx, side: size.width) } }
                    Color.clear.contentShape(Rectangle()).gesture(aimGesture(side: side))
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            VStack(spacing: 4) {
                Slider(value: $model.strikerX, in: 0 ... 1).disabled(!model.canShoot).tint(Theme.accent)
                Text(model.canShoot ? "Slide to place the striker, then pull back on the board and release" : " ").font(.footnote).foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var scoreBar: some View {
        HStack(spacing: 14) {
            ForEach(0 ..< 2, id: \.self) { s in
                HStack(spacing: 6) {
                    Circle().fill(s == 0 ? Color(white: 0.95) : Color(white: 0.12)).frame(width: 14, height: 14).overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                    Text("\(model.game.score[s])").font(.system(size: 22, weight: .heavy, design: .rounded)).contentTransition(.numericText())
                    Text("\(model.game.remaining(s == 0 ? .white : .black)) left").font(.caption).foregroundStyle(Theme.text2)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(model.game.turn == s && !model.game.over ? Theme.surface2 : Theme.surface, in: Capsule())
            }
            if model.game.queenState == 2 { Label("Queen", systemImage: "crown.fill").font(.caption).foregroundStyle(.red) }
        }
        .animation(.snappy, value: model.game.score)
    }

    // MARK: Input

    private func toBoard(_ p: CGPoint, side: CGFloat) -> SIMD2<Double> {
        let x = Double(p.x / side), y = Double(p.y / side)
        return flipped ? SIMD2(1 - x, 1 - y) : SIMD2(x, y)
    }

    private func aimGesture(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard model.canShoot else { aim = nil; return }
                aim = CGSize(width: v.location.x - v.startLocation.x, height: v.location.y - v.startLocation.y)
            }
            .onEnded { v in
                defer { aim = nil }
                guard model.canShoot else { return }
                // Pull back: the shot goes the opposite way to the drag.
                var dx = -Double(v.translation.width / side), dy = -Double(v.translation.height / side)
                if flipped { dx = -dx; dy = -dy }
                let len = (dx * dx + dy * dy).squareRoot()
                guard len > 0.035 else { return }
                let power = min(1, len / 0.32)
                let speed = 0.8 + power * (CarromWorld.maxShotSpeed - 0.8)
                model.shoot(vx: dx / len * speed, vy: dy / len * speed)
            }
    }

    // MARK: Drawing

    private func pt(_ p: SIMD2<Double>, _ s: CGFloat) -> CGPoint {
        let q = flipped ? SIMD2(1 - p.x, 1 - p.y) : p
        return CGPoint(x: q.x * s, y: q.y * s)
    }

    private func draw(_ ctx: inout GraphicsContext, side s: CGFloat) {
        // Frame and surface.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: s, height: s)), with: .linearGradient(Gradient(colors: [Color(red: 0.93, green: 0.78, blue: 0.5), Color(red: 0.86, green: 0.68, blue: 0.4)]), startPoint: .zero, endPoint: CGPoint(x: s, y: s)))
        let line = Color(red: 0.35, green: 0.2, blue: 0.1).opacity(0.8)
        ctx.stroke(Path(CGRect(x: 0.06 * s, y: 0.06 * s, width: 0.88 * s, height: 0.88 * s)), with: .color(line), lineWidth: 1.5)
        ctx.stroke(Path(ellipseIn: CGRect(x: 0.5 * s - 0.09 * s, y: 0.5 * s - 0.09 * s, width: 0.18 * s, height: 0.18 * s)), with: .color(line), lineWidth: 1.5)
        ctx.stroke(Path(ellipseIn: CGRect(x: 0.5 * s - 0.2 * s, y: 0.5 * s - 0.2 * s, width: 0.4 * s, height: 0.4 * s)), with: .color(line.opacity(0.6)), lineWidth: 1)
        ctx.fill(Path(ellipseIn: CGRect(x: 0.5 * s - 0.012 * s, y: 0.5 * s - 0.012 * s, width: 0.024 * s, height: 0.024 * s)), with: .color(Color(red: 0.75, green: 0.1, blue: 0.1)))
        for seat in 0 ..< 2 {
            let y = CarromGame.baselineY(seat)
            let a = pt(SIMD2(0.17, y), s), b = pt(SIMD2(0.83, y), s)
            ctx.stroke(Path { p in p.move(to: a); p.addLine(to: b) }, with: .color(line.opacity(0.5)), lineWidth: 1)
            for x in [0.17, 0.83] { let c = pt(SIMD2(x, y), s); ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 0.03 * s, y: c.y - 0.03 * s, width: 0.06 * s, height: 0.06 * s)), with: .color(Color(red: 0.75, green: 0.15, blue: 0.15).opacity(0.7)), lineWidth: 1.5) }
        }
        // Pockets.
        for c in CarromWorld.corners {
            let q = pt(c, s), r = CGFloat(CarromWorld.pocketR) * s
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)), with: .radialGradient(Gradient(colors: [.black, Color(white: 0.12)]), center: q, startRadius: 0, endRadius: r))
        }
        // Pieces.
        let pieces = model.phase == .moving ? model.world.pieces : model.game.pieces
        for p in pieces where !p.pocketed { drawPiece(&ctx, p, s) }
        // Striker while aiming.
        if model.phase == .aiming, !model.game.over {
            let x = CarromGame.baselineRange.lowerBound + model.strikerX * (CarromGame.baselineRange.upperBound - CarromGame.baselineRange.lowerBound)
            let sp = model.session.mySeats.contains(model.game.turn) ? x : 0.5
            let striker = CarromPiece(id: 99, kind: .striker, p: SIMD2(sp, CarromGame.baselineY(model.game.turn)))
            drawPiece(&ctx, striker, s)
            if let aim, model.canShoot {
                var dx = -Double(aim.width / s), dy = -Double(aim.height / s)
                if flipped { dx = -dx; dy = -dy }
                let len = (dx * dx + dy * dy).squareRoot()
                if len > 0.01 {
                    let power = min(1, len / 0.32)
                    let from = pt(striker.p, s)
                    let dir = CGPoint(x: (flipped ? -dx : dx) / len, y: (flipped ? -dy : dy) / len)
                    let end = CGPoint(x: from.x + dir.x * s * (0.2 + 0.5 * power), y: from.y + dir.y * s * (0.2 + 0.5 * power))
                    ctx.stroke(Path { p in p.move(to: from); p.addLine(to: end) }, with: .color(Color.white.opacity(0.9)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 7]))
                    ctx.fill(Path(ellipseIn: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10)), with: .color(Color(hue: 0.33 * (1 - power), saturation: 0.9, brightness: 1)))
                }
            }
        }
    }

    private func drawPiece(_ ctx: inout GraphicsContext, _ p: CarromPiece, _ s: CGFloat) {
        let c = pt(p.p, s), r = CGFloat(p.radius) * s
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r + 1, y: c.y - r + 2.5, width: r * 2, height: r * 2)), with: .color(.black.opacity(0.35)))
        let (light, dark): (Color, Color)
        switch p.kind {
        case .white: (light, dark) = (Color(red: 1, green: 0.97, blue: 0.88), Color(red: 0.82, green: 0.76, blue: 0.62))
        case .black: (light, dark) = (Color(white: 0.38), Color(white: 0.04))
        case .queen: (light, dark) = (Color(red: 1, green: 0.45, blue: 0.45), Color(red: 0.7, green: 0.05, blue: 0.1))
        case .striker: (light, dark) = (Color(red: 0.7, green: 0.9, blue: 1), Color(red: 0.15, green: 0.45, blue: 0.9))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .radialGradient(Gradient(colors: [light, dark]), center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.35), startRadius: 0, endRadius: r * 1.4))
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.62, y: c.y - r * 0.62, width: r * 1.24, height: r * 1.24)), with: .color(dark.opacity(0.55)), lineWidth: max(1, r * 0.1))
        if p.kind == .striker { ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.3, y: c.y - r * 0.3, width: r * 0.6, height: r * 0.6)), with: .color(.white.opacity(0.7)), lineWidth: 1.5) }
    }
}
