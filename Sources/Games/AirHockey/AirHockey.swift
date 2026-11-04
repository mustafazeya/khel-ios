import SwiftUI

// MARK: - Physics (pure)

/// Table physics in table units: 1.0 wide, 1.6 tall. Seat 0 defends the bottom goal, seat 1 the top goal.
struct AirHockeyPhysics: Equatable, Sendable {
    static let W = 1.0, H = 1.6
    static let puckR = 0.045, malletR = 0.075, goalWidth = 0.40, postR = 0.022
    static let winScore = 7
    static let maxPuckSpeed = 3.4
    static let maxMalletSpeed = 5.0

    enum Phase: UInt8, Sendable { case countdown = 0, playing, goal, over }
    enum Event: Equatable, Sendable { case wall, hit, goal(scorer: Int), start }

    var puck = SIMD2<Double>(W / 2, H / 2)
    var vel = SIMD2<Double>(0, 0)
    var mallet = [SIMD2<Double>(W / 2, H - 0.2), SIMD2<Double>(W / 2, 0.2)]
    var malletVel = [SIMD2<Double>(0, 0), SIMD2<Double>(0, 0)]
    var target = [SIMD2<Double>(W / 2, H - 0.2), SIMD2<Double>(W / 2, 0.2)]
    var score = [0, 0]
    var phase = Phase.countdown
    var timer = 2.4
    var winner: Int?

    static func clampMallet(_ p: SIMD2<Double>, seat: Int) -> SIMD2<Double> {
        let r = malletR
        let y = seat == 0 ? min(max(p.y, H / 2 + r), H - r) : min(max(p.y, r), H / 2 - r)
        return SIMD2(min(max(p.x, r), W - r), y)
    }

    mutating func setTarget(_ p: SIMD2<Double>, seat: Int) { target[seat] = Self.clampMallet(p, seat: seat) }

    private mutating func moveMallets(_ dt: Double, speeds: [Double]) {
        guard dt > 0 else { return }
        for s in 0 ..< 2 {
            var d = target[s] - mallet[s]
            let len = (d.x * d.x + d.y * d.y).squareRoot()
            let maxStep = speeds[s] * dt
            if len > maxStep { d *= maxStep / len }
            let new = Self.clampMallet(mallet[s] + d, seat: s)
            malletVel[s] = (new - mallet[s]) / dt
            mallet[s] = new
        }
    }

    private mutating func resetPuck(towards seat: Int) {
        puck = SIMD2(Self.W / 2, seat == 1 ? Self.H * 0.3 : Self.H * 0.7)
        vel = SIMD2(0, 0)
    }

    mutating func step(_ dt: Double, speeds: [Double] = [maxMalletSpeed, maxMalletSpeed]) -> [Event] {
        var events: [Event] = []
        moveMallets(dt, speeds: speeds)
        switch phase {
        case .countdown:
            timer -= dt
            if timer <= 0 { phase = .playing; events.append(.start) }
        case .goal:
            timer -= dt
            if timer <= 0 {
                if let w = score.firstIndex(where: { $0 >= Self.winScore }) { phase = .over; winner = w }
                else { phase = .countdown; timer = 1.8 }
            }
        case .over:
            break
        case .playing:
            let n = max(1, Int((dt / (1.0 / 240)).rounded(.up)))
            let h = dt / Double(n)
            for _ in 0 ..< n {
                puck += vel * h
                vel *= 1 - 0.22 * h
                events += collideWalls()
                for s in 0 ..< 2 { if let e = collideMallet(s) { events.append(e) } }
                let speed = (vel.x * vel.x + vel.y * vel.y).squareRoot()
                if speed > Self.maxPuckSpeed { vel *= Self.maxPuckSpeed / speed }
                if let g = goalCheck() { events.append(g); break }
            }
        }
        return events
    }

    private mutating func collideWalls() -> [Event] {
        var events: [Event] = []
        let r = Self.puckR
        if puck.x < r { puck.x = r; vel.x = abs(vel.x) * 0.94; events.append(.wall) }
        if puck.x > Self.W - r { puck.x = Self.W - r; vel.x = -abs(vel.x) * 0.94; events.append(.wall) }
        let inGoal = abs(puck.x - Self.W / 2) < Self.goalWidth / 2 - r * 0.3
        if puck.y < r, !inGoal { puck.y = r; vel.y = abs(vel.y) * 0.94; events.append(.wall) }
        if puck.y > Self.H - r, !inGoal { puck.y = Self.H - r; vel.y = -abs(vel.y) * 0.94; events.append(.wall) }
        // Goal posts.
        for py in [0.0, Self.H] { for px in [Self.W / 2 - Self.goalWidth / 2, Self.W / 2 + Self.goalWidth / 2] {
            let post = SIMD2(px, py)
            let d = puck - post
            let dist = (d.x * d.x + d.y * d.y).squareRoot()
            if dist < r + Self.postR, dist > 0 {
                let n = d / dist
                puck = post + n * (r + Self.postR)
                let vn = vel.x * n.x + vel.y * n.y
                if vn < 0 { vel -= 1.9 * vn * n; events.append(.wall) }
            }
        } }
        return events
    }

    private mutating func collideMallet(_ s: Int) -> Event? {
        let d = puck - mallet[s]
        let dist = (d.x * d.x + d.y * d.y).squareRoot()
        let minDist = Self.puckR + Self.malletR
        guard dist < minDist else { return nil }
        let n = dist > 1e-9 ? d / dist : SIMD2(0, s == 0 ? -1 : 1)
        puck = mallet[s] + n * minDist
        let rel = vel - malletVel[s]
        let vn = rel.x * n.x + rel.y * n.y
        guard vn < 0 else { return nil }
        vel -= 1.92 * vn * n
        return .hit
    }

    private mutating func goalCheck() -> Event? {
        let scorer: Int
        if puck.y < -Self.puckR { scorer = 0 } else if puck.y > Self.H + Self.puckR { scorer = 1 } else { return nil }
        score[scorer] += 1
        phase = .goal
        timer = 1.3
        resetPuck(towards: 1 - scorer)
        return .goal(scorer: scorer)
    }

    // MARK: Snapshots

    /// Compact binary state for the 60 Hz network stream.
    func snapshot() -> Data {
        var d = Data([1])
        func put(_ v: Double) { var f = Float32(v); withUnsafeBytes(of: &f) { d.append(contentsOf: $0) } }
        for v in [puck.x, puck.y, vel.x, vel.y, mallet[0].x, mallet[0].y, mallet[1].x, mallet[1].y, timer] { put(v) }
        d.append(contentsOf: [UInt8(score[0]), UInt8(score[1]), phase.rawValue])
        return d
    }

    static let snapshotSize = 1 + 9 * 4 + 3

    mutating func apply(snapshot d: Data) -> Bool {
        guard d.count == Self.snapshotSize, d.first == 1 else { return false }
        func get(_ i: Int) -> Double { Double(d.subdata(in: (1 + i * 4) ..< (5 + i * 4)).withUnsafeBytes { $0.loadUnaligned(as: Float32.self) }) }
        puck = SIMD2(get(0), get(1)); vel = SIMD2(get(2), get(3))
        mallet[0] = SIMD2(get(4), get(5)); mallet[1] = SIMD2(get(6), get(7))
        timer = get(8)
        score = [Int(d[37]), Int(d[38])]
        phase = Phase(rawValue: d[39]) ?? .playing
        return true
    }

    static func inputPacket(_ p: SIMD2<Double>) -> Data {
        var d = Data([2])
        for v in [p.x, p.y] { var f = Float32(v); withUnsafeBytes(of: &f) { d.append(contentsOf: $0) } }
        return d
    }

    static func decodeInput(_ d: Data) -> SIMD2<Double>? {
        guard d.count == 9, d.first == 2 else { return nil }
        func get(_ i: Int) -> Double { Double(d.subdata(in: (1 + i * 4) ..< (5 + i * 4)).withUnsafeBytes { $0.loadUnaligned(as: Float32.self) }) }
        return SIMD2(get(0), get(1))
    }

    // MARK: Computer opponent

    /// Where a computer-controlled mallet wants to be and how fast it may move.
    func aiTarget(seat: Int, level: AILevel, noise: Double) -> (SIMD2<Double>, Double) {
        let speed: Double = level == .easy ? 0.9 : (level == .medium ? 1.5 : 2.4)
        let dir: Double = seat == 1 ? 1 : -1          // direction pointing into the AI's own half from its goal line
        let homeY = seat == 1 ? 0.16 : Self.H - 0.16
        let towardsMe = seat == 1 ? vel.y < -0.08 : vel.y > 0.08
        let ownHalf = seat == 1 ? puck.y < Self.H / 2 : puck.y > Self.H / 2
        let oppGoal = SIMD2(Self.W / 2, seat == 1 ? Self.H : 0)

        if towardsMe, abs(vel.y) > 0.01 {
            let t = (homeY - puck.y) / vel.y
            var x = puck.x + vel.x * t
            let span = Self.W - 2 * Self.puckR
            var u = (x - Self.puckR).truncatingRemainder(dividingBy: 2 * span)
            if u < 0 { u += 2 * span }
            x = Self.puckR + (u > span ? 2 * span - u : u)
            // A hard opponent steps forward to meet the puck.
            let y = level == .hard && ownHalf ? homeY + dir * 0.12 : homeY
            return (SIMD2(x + noise, y), speed)
        }
        if ownHalf, (vel.x * vel.x + vel.y * vel.y).squareRoot() < 0.9 {
            var d = oppGoal - puck
            let len = (d.x * d.x + d.y * d.y).squareRoot()
            d /= max(len, 1e-6)
            let behind = puck - d * (Self.puckR + Self.malletR - 0.012)
            // Swing through the puck once lined up behind it.
            let lined = (mallet[seat] - behind).x.magnitude < 0.05 && (mallet[seat] - behind).y.magnitude < 0.07
            let aim = lined ? puck + d * 0.12 : behind
            return (SIMD2(aim.x + noise * 0.3, aim.y), speed * (lined ? 1.6 : 1))
        }
        return (SIMD2(Self.W / 2 + noise, homeY + dir * 0.08), speed)
    }
}

// MARK: - Model

@MainActor @Observable
private final class AirHockeyModel {
    var phys = AirHockeyPhysics()
    var trail: [SIMD2<Double>] = []
    var flash = 0.0
    private(set) var session: RealtimeSession
    private var loop: Task<Void, Never>?
    private var snapshots: [(time: TimeInterval, state: AirHockeyPhysics)] = []
    private var level: AILevel = .medium
    private var lastScore = [0, 0]
    private var lastPhase = AirHockeyPhysics.Phase.countdown
    private var noiseSeed = SplitMix64(seed: 7)
    private var noise = 0.0
    private var noiseUntil = 0.0

    init(session: RealtimeSession, level: AILevel) {
        self.session = session
        self.level = level
        session.onMessage = { [weak self] data, seat in self?.receive(data, from: seat) }
        session.onReset = { [weak self] in self?.reset() }
    }

    var isAuthority: Bool { session.isAuthority }
    private var humanSeats: Set<Int> { session.mySeats }

    func start() {
        loop?.cancel()
        loop = Task { @MainActor [weak self] in
            var last = ContinuousClock.now
            var sendClock = 0.0
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(8))
                let now = ContinuousClock.now
                let dt = min(0.05, Double((now - last).components.seconds) + Double((now - last).components.attoseconds) / 1e18)
                last = now
                if self.isAuthority { self.simulate(dt) } else { self.advanceClient() }
                sendClock += dt
                if sendClock >= 1.0 / 60 {
                    sendClock = 0
                    self.network()
                }
            }
        }
    }

    func stop() { loop?.cancel() }

    func reset() {
        phys = AirHockeyPhysics()
        snapshots = []
        lastScore = [0, 0]
        lastPhase = .countdown
    }

    func rematch() { session.rematch() }

    // MARK: Authority

    private func simulate(_ dt: Double) {
        guard session.outcome == nil else { return }
        var speeds = [AirHockeyPhysics.maxMalletSpeed, AirHockeyPhysics.maxMalletSpeed]
        for seat in session.aiSeats {
            let now = Date().timeIntervalSinceReferenceDate
            if now > noiseUntil {
                noiseUntil = now + 0.4
                let spread: Double = level == .easy ? 0.16 : (level == .medium ? 0.07 : 0.02)
                noise = (Double(noiseSeed.int(in: -1000 ... 1000)) / 1000) * spread
            }
            let (t, sp) = phys.aiTarget(seat: seat, level: level, noise: noise)
            phys.setTarget(t, seat: seat)
            speeds[seat] = sp
        }
        let events = phys.step(dt, speeds: speeds)
        react(events)
        trail.append(phys.puck); if trail.count > 14 { trail.removeFirst() }
        if phys.phase == .over, let w = phys.winner {
            session.status = "\(session.seats[w].name) wins"
            session.finish(.win(w, others: [1 - w], summary: "\(phys.score[w]) – \(phys.score[1 - w])"))
        }
    }

    private func react(_ events: [AirHockeyPhysics.Event]) {
        for e in events {
            switch e {
            case .hit: Feedback.shared.thud(); Feedback.shared.play(.tap)
            case .wall: Feedback.shared.play(.place)
            case .goal(let scorer):
                flash = 1
                if humanSeats.contains(scorer) { Feedback.shared.success() } else { Feedback.shared.failure() }
            case .start: Feedback.shared.tap()
            }
        }
    }

    // MARK: Network

    private func network() {
        guard session.isNetworked else { return }
        if isAuthority { session.send(phys.snapshot()) }
        else if let seat = humanSeats.min() { session.send(AirHockeyPhysics.inputPacket(phys.target[seat])) }
    }

    private func receive(_ data: Data, from seat: Int) {
        if data.isEmpty { return }
        if isAuthority {
            if let p = AirHockeyPhysics.decodeInput(data), seat >= 0, seat < 2 { phys.setTarget(p, seat: seat) }
        } else {
            var s = phys
            if s.apply(snapshot: data) { snapshots.append((Date().timeIntervalSinceReferenceDate, s)); if snapshots.count > 6 { snapshots.removeFirst() } }
        }
    }

    /// Renders the host's snapshots about 50 ms in the past, blending between the two around that time.
    private func advanceClient() {
        guard !snapshots.isEmpty else { return }
        let renderTime = Date().timeIntervalSinceReferenceDate - 0.05
        var a = snapshots[0], b = snapshots[snapshots.count - 1]
        for i in 0 ..< snapshots.count - 1 where snapshots[i].time <= renderTime && snapshots[i + 1].time >= renderTime { a = snapshots[i]; b = snapshots[i + 1]; break }
        let span = b.time - a.time
        let k = span > 0 ? min(1, max(0, (renderTime - a.time) / span)) : 1
        var s = b.state
        s.puck = a.state.puck + (b.state.puck - a.state.puck) * k
        let opp = 1 - (humanSeats.min() ?? 0)
        s.mallet[opp] = a.state.mallet[opp] + (b.state.mallet[opp] - a.state.mallet[opp]) * k
        // Our own mallet follows the finger locally for zero latency.
        let me = humanSeats.min() ?? 0
        s.mallet[me] = phys.mallet[me]
        let oldScore = phys.score, oldPhase = phys.phase
        phys.puck = s.puck; phys.vel = s.vel
        phys.mallet[opp] = s.mallet[opp]
        phys.score = b.state.score; phys.phase = b.state.phase; phys.timer = b.state.timer
        // The client's own mallet moves toward its target at the same speed limit.
        phys.setTarget(phys.target[me], seat: me)
        let d = phys.target[me] - phys.mallet[me]
        phys.mallet[me] = AirHockeyPhysics.clampMallet(phys.mallet[me] + d * 0.6, seat: me)
        if phys.score != oldScore, let scorer = phys.score.indices.first(where: { phys.score[$0] > oldScore[$0] }) {
            flash = 1; humanSeats.contains(scorer) ? Feedback.shared.success() : Feedback.shared.failure()
        }
        if oldPhase != phys.phase, phys.phase == .playing { Feedback.shared.tap() }
        trail.append(phys.puck); if trail.count > 14 { trail.removeFirst() }
    }
}

// MARK: - View

struct AirHockeyView: View {
    static let info = GameInfo(
        id: "airhockey", title: "Air Hockey", tagline: "Fast, smooth, head-to-head", symbol: "sportscourt.fill", origin: .arcade, mode: .realtime,
        minPlayers: 2, maxPlayers: 2, palette: [0x00C6FF, 0x0072FF], supportsAI: true,
        rules: "Drag your mallet to hit the puck into your opponent's goal. First to 7 goals wins. Move fast to hit harder. On two phones each player controls their own mallet on their own screen; on one phone, two players each use their half of the table.")

    let session: RealtimeSession
    @State private var model: AirHockeyModel

    init(session: RealtimeSession) {
        self.session = session
        let level = session.launch.seats.compactMap { seat -> AILevel? in if case .ai(let l) = seat.kind { l } else { nil } }.first ?? .medium
        _model = State(initialValue: AirHockeyModel(session: session, level: level))
    }

    private var flipped: Bool { session.mySeats == [1] }
    private var twoLocal: Bool { session.mySeats.count == 2 }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / AirHockeyPhysics.W, geo.size.height / AirHockeyPhysics.H)
            let w = scale * AirHockeyPhysics.W, h = scale * AirHockeyPhysics.H
            ZStack {
                TimelineView(.animation) { _ in
                    Canvas { ctx, size in draw(&ctx, size: size, scale: scale) }
                }
                .frame(width: w, height: h)
                overlay(w: w, h: h)
                touchLayer(scale: scale, w: w, h: h)
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .onAppear { model.start(); session.status = "First to 7" }
        .onDisappear { model.stop() }
    }

    // MARK: Input

    private func canonical(_ p: CGPoint, scale: CGFloat, w: CGFloat, h: CGFloat) -> SIMD2<Double> {
        let x = Double(p.x / scale), y = Double(p.y / scale)
        return flipped ? SIMD2(AirHockeyPhysics.W - x, AirHockeyPhysics.H - y) : SIMD2(x, y)
    }

    @ViewBuilder private func touchLayer(scale: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        if twoLocal {
            VStack(spacing: 0) {
                zone(seat: 1, scale: scale, w: w, h: h, originY: 0).frame(height: h / 2)
                zone(seat: 0, scale: scale, w: w, h: h, originY: h / 2).frame(height: h / 2)
            }
        } else if let seat = session.mySeats.min() {
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    model.phys.setTarget(canonical(v.location, scale: scale, w: w, h: h), seat: seat)
                })
        }
    }

    private func zone(seat: Int, scale: CGFloat, w: CGFloat, h: CGFloat, originY: CGFloat) -> some View {
        Color.clear.contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                model.phys.setTarget(SIMD2(Double(v.location.x / scale), Double((v.location.y + originY) / scale)), seat: seat)
            })
    }

    // MARK: Drawing

    private func map(_ p: SIMD2<Double>, scale: CGFloat) -> CGPoint {
        let q = flipped ? SIMD2(AirHockeyPhysics.W - p.x, AirHockeyPhysics.H - p.y) : p
        return CGPoint(x: q.x * scale, y: q.y * scale)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, scale: CGFloat) {
        let W = size.width, H = size.height
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [Color(red: 0.04, green: 0.12, blue: 0.22), Color(red: 0.02, green: 0.07, blue: 0.14)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: H)))
        let line = Color(red: 0.3, green: 0.8, blue: 1).opacity(0.55)
        ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: H / 2)); p.addLine(to: CGPoint(x: W, y: H / 2)) }, with: .color(line), lineWidth: 3)
        ctx.stroke(Path(ellipseIn: CGRect(x: W / 2 - W * 0.17, y: H / 2 - W * 0.17, width: W * 0.34, height: W * 0.34)), with: .color(line), lineWidth: 3)
        let gw = CGFloat(AirHockeyPhysics.goalWidth) * scale
        for top in [true, false] {
            let y: CGFloat = top ? 0 : H
            ctx.fill(Path(CGRect(x: (W - gw) / 2, y: top ? 0 : H - 8, width: gw, height: 8)), with: .color(.black))
            ctx.stroke(Path { p in p.addArc(center: CGPoint(x: W / 2, y: y), radius: gw * 0.62, startAngle: .degrees(top ? 0 : 180), endAngle: .degrees(top ? 180 : 360), clockwise: !top) },
                       with: .color(line), lineWidth: 3)
        }
        // Scores, faint and large.
        let topSeat = flipped ? 0 : 1, bottomSeat = flipped ? 1 : 0
        ctx.draw(Text("\(model.phys.score[topSeat])").font(.system(size: W * 0.34, weight: .black, design: .rounded)).foregroundStyle(Color.white.opacity(0.07)), at: CGPoint(x: W / 2, y: H * 0.27))
        ctx.draw(Text("\(model.phys.score[bottomSeat])").font(.system(size: W * 0.34, weight: .black, design: .rounded)).foregroundStyle(Color.white.opacity(0.07)), at: CGPoint(x: W / 2, y: H * 0.73))

        // Puck trail and puck.
        let pr = CGFloat(AirHockeyPhysics.puckR) * scale
        for (i, p) in model.trail.enumerated() {
            let a = Double(i) / Double(max(1, model.trail.count))
            let c = map(p, scale: scale)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - pr * 0.8, y: c.y - pr * 0.8, width: pr * 1.6, height: pr * 1.6)), with: .color(.white.opacity(a * 0.12)))
        }
        let pc = map(model.phys.puck, scale: scale)
        ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pr * 2, y: pc.y - pr * 2, width: pr * 4, height: pr * 4)), with: .radialGradient(Gradient(colors: [.white.opacity(0.35), .clear]), center: pc, startRadius: 0, endRadius: pr * 2))
        ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pr, y: pc.y - pr, width: pr * 2, height: pr * 2)), with: .radialGradient(Gradient(colors: [.white, Color(white: 0.7)]), center: CGPoint(x: pc.x - pr * 0.3, y: pc.y - pr * 0.3), startRadius: 0, endRadius: pr * 1.3))

        // Mallets.
        let mr = CGFloat(AirHockeyPhysics.malletR) * scale
        for seat in 0 ..< 2 {
            let c = map(model.phys.mallet[seat], scale: scale)
            let color = seat == 0 ? Color(red: 0.2, green: 0.55, blue: 1) : Color(red: 1, green: 0.3, blue: 0.35)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - mr * 1.5, y: c.y - mr * 1.5, width: mr * 3, height: mr * 3)), with: .radialGradient(Gradient(colors: [color.opacity(0.4), .clear]), center: c, startRadius: 0, endRadius: mr * 1.5))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - mr, y: c.y - mr + 3, width: mr * 2, height: mr * 2)), with: .color(.black.opacity(0.4)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - mr, y: c.y - mr, width: mr * 2, height: mr * 2)), with: .radialGradient(Gradient(colors: [color.opacity(0.7), color]), center: CGPoint(x: c.x - mr * 0.3, y: c.y - mr * 0.3), startRadius: 0, endRadius: mr * 1.3))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - mr * 0.55, y: c.y - mr * 0.55, width: mr * 1.1, height: mr * 1.1)), with: .color(.white.opacity(0.55)), lineWidth: 3)
        }
        if model.flash > 0 { ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.12 * model.flash))) }
    }

    @ViewBuilder private func overlay(w: CGFloat, h: CGFloat) -> some View {
        let p = model.phys
        if p.phase == .countdown {
            Text(p.timer > 1.2 ? "\(Int((p.timer - 1.2).rounded(.up)))" : "GO")
                .font(.system(size: 90, weight: .black, design: .rounded)).foregroundStyle(.white).shadow(radius: 10)
        } else if p.phase == .goal {
            Text("GOAL!").font(.system(size: 54, weight: .black, design: .rounded)).foregroundStyle(.yellow).shadow(radius: 10)
        }
        if model.session.outcome != nil { Color.clear }
    }
}
