import SwiftUI

private struct ExitGameKey: EnvironmentKey { static let defaultValue: @MainActor @Sendable () -> Void = {} }

extension EnvironmentValues {
    /// Leaves the current game (returns to the lobby or the catalog). Set by the game container.
    var exitGame: @MainActor @Sendable () -> Void {
        get { self[ExitGameKey.self] }
        set { self[ExitGameKey.self] = newValue }
    }
}

// MARK: - Screens

struct TurnGameScreen<E: TurnEngine, Board: View>: View {
    @State private var session: TurnSession<E>
    let room: RoomSession?
    let board: @MainActor (TurnSession<E>) -> Board

    init(launch: GameLaunch, room: RoomSession?, board: @escaping @MainActor (TurnSession<E>) -> Board) {
        _session = State(initialValue: TurnSession<E>(launch: launch, room: room))
        self.room = room
        self.board = board
    }

    var body: some View {
        GameChrome(info: E.info, seats: session.seats, mySeats: session.mySeats, activeSeat: session.activeSeat,
                   status: session.status, outcome: session.outcome, notice: session.notice,
                   waiting: session.waitingForPlayer, networked: session.isNetworked, isHost: session.role != .client,
                   room: room,
                   onRematch: { session.rematch() },
                   onReplaceWithAI: { session.replaceWithAI(seat: $0) }) {
            board(session)
        }
        .onChange(of: session.version) { _, _ in Feedback.shared.play(.place) }
        .onChange(of: session.outcome) { _, o in celebrate(o, mySeats: session.mySeats) }
        .onDisappear { session.close() }
    }
}

struct RealtimeGameScreen<Content: View>: View {
    @State private var session: RealtimeSession
    let info: GameInfo
    let room: RoomSession?
    let content: @MainActor (RealtimeSession) -> Content

    init(info: GameInfo, launch: GameLaunch, room: RoomSession?, content: @escaping @MainActor (RealtimeSession) -> Content) {
        _session = State(initialValue: RealtimeSession(launch: launch, room: room))
        self.info = info
        self.room = room
        self.content = content
    }

    var body: some View {
        GameChrome(info: info, seats: session.seats, mySeats: session.mySeats, activeSeat: nil,
                   status: session.status, outcome: session.outcome, notice: nil, waiting: nil,
                   networked: session.isNetworked, isHost: session.isAuthority, room: room,
                   onRematch: { session.rematch() }, onReplaceWithAI: { _ in }) {
            content(session)
        }
        .onChange(of: session.outcome) { _, o in celebrate(o, mySeats: session.mySeats) }
        .onDisappear { session.close() }
    }
}

struct SoloGameScreen<Content: View>: View {
    let info: GameInfo
    let content: @MainActor () -> Content
    @Environment(\.exitGame) private var exit

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { exit() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 36, height: 36)
                        .background(Theme.surface2, in: Circle())
                }
                Spacer()
                Label(info.title, systemImage: info.symbol).font(.khHeadline)
                Spacer()
                HowToPlayButton(info: info)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            content()
        }
        .foregroundStyle(.white)
        .background(Theme.bg.ignoresSafeArea())
    }
}

@MainActor
private func celebrate(_ outcome: Outcome?, mySeats: Set<Int>) {
    guard let outcome else { return }
    if let first = outcome.ranking.first, !outcome.isDraw, mySeats.contains(first) { Feedback.shared.success() } else { Feedback.shared.play(.lose) }
}

// MARK: - Chrome

struct GameChrome<Content: View>: View {
    let info: GameInfo
    let seats: [SeatConfig]
    let mySeats: Set<Int>
    let activeSeat: Int?
    let status: String
    let outcome: Outcome?
    let notice: String?
    let waiting: SeatConfig?
    let networked: Bool
    let isHost: Bool
    let room: RoomSession?
    let onRematch: () -> Void
    let onReplaceWithAI: (Int) -> Void
    @ViewBuilder var content: Content

    @Environment(\.exitGame) private var exit
    @State private var confirmExit = false
    @State private var emote: Emote?

    private static var emotes: [String] { ["👏", "😂", "😮", "😡", "🔥", "🙏", "GG"] }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 10) {
                topBar
                seatStrip
                Text(status.isEmpty ? " " : status)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .contentTransition(.opacity)
                    .animation(.snappy, value: status)
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
                if let notice { Text(notice).font(.footnote).foregroundStyle(Theme.bad).transition(.opacity) }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .foregroundStyle(.white)

            if let waiting { waitingBanner(waiting) }
            if let emote { emoteBubble(emote) }
            if let outcome { ResultOverlay(outcome: outcome, seats: seats, mySeats: mySeats, canRematch: isHost, onRematch: onRematch, onLeave: { exit() }) }
        }
        .confirmationDialog("Leave this game?", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("Leave game", role: .destructive) { exit() }
            Button("Keep playing", role: .cancel) {}
        }
        .onChange(of: room?.lastEmote) { _, e in
            guard let e else { return }
            withAnimation(.spring) { emote = e }
            Task {
                try? await Task.sleep(for: .seconds(2.4))
                if emote?.id == e.id { withAnimation { emote = nil } }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button { outcome == nil ? (confirmExit = true) : exit() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 36, height: 36)
                    .background(Theme.surface2, in: Circle())
            }
            .accessibilityLabel("Leave game")
            Spacer()
            Label(info.title, systemImage: info.symbol).font(.khHeadline)
            Spacer()
            HStack(spacing: 8) {
                HowToPlayButton(info: info)
                if networked {
                    Menu {
                        ForEach(Self.emotes, id: \.self) { e in
                            Button(e) { room?.sendEmote(e, seat: mySeats.min()) }
                        }
                    } label: {
                        Image(systemName: "face.smiling").font(.system(size: 16, weight: .bold)).frame(width: 36, height: 36)
                            .background(Theme.surface2, in: Circle())
                    }
                    .accessibilityLabel("Send reaction")
                }
            }
        }
        .padding(.top, 4)
    }

    private var seatStrip: some View {
        HStack(spacing: 10) {
            ForEach(seats) { seat in
                SeatChip(seat: seat, active: activeSeat == seat.index, mine: networked && mySeats.contains(seat.index),
                         color: Theme.seatColors[seat.index % Theme.seatColors.count])
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func waitingBanner(_ seat: SeatConfig) -> some View {
        VStack {
            Spacer()
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Waiting for \(seat.name) to reconnect", systemImage: "wifi.exclamationmark").font(.headline)
                    if isHost {
                        Button("Let the computer play for \(seat.name)") { onReplaceWithAI(seat.index) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            .padding()
        }
        .transition(.move(edge: .bottom))
    }

    private func emoteBubble(_ e: Emote) -> some View {
        VStack {
            Text("\(e.from)  \(e.emoji)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 96)
            Spacer()
        }
        .transition(.scale.combined(with: .opacity))
        .allowsHitTesting(false)
    }
}

struct SeatChip: View {
    let seat: SeatConfig
    let active: Bool
    let mine: Bool
    let color: Color
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(spec: seat.avatar, size: 44, ring: active ? color : color.opacity(0.35))
                    .scaleEffect(active && pulse ? 1.06 : 1)
                    .shadow(color: active ? color.opacity(0.7) : .clear, radius: 8)
                if seat.kind.isAI {
                    Text("AI").font(.system(size: 9, weight: .heavy)).padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Theme.surface2, in: Capsule())
                } else if !seat.connected {
                    Image(systemName: "wifi.slash").font(.system(size: 10, weight: .bold)).padding(3)
                        .background(Theme.bad, in: Circle())
                }
            }
            Text(mine ? "\(seat.name) (you)" : seat.name)
                .font(.system(size: 11, weight: active ? .bold : .medium, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(active ? .white : Theme.text2)
        }
        .animation(.snappy, value: active)
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

// MARK: - Result

struct ResultOverlay: View {
    let outcome: Outcome
    let seats: [SeatConfig]
    let mySeats: Set<Int>
    let canRematch: Bool
    let onRematch: () -> Void
    let onLeave: () -> Void

    private var iWon: Bool { !outcome.isDraw && (outcome.ranking.first.map(mySeats.contains) ?? false) }

    private var headline: String {
        if outcome.isDraw { return "It's a draw" }
        guard let w = outcome.ranking.first, seats.indices.contains(w) else { return "Game over" }
        if iWon { return mySeats.count > 1 ? "\(seats[w].name) wins!" : "You won!" }
        return "\(seats[w].name) wins"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            if iWon { Confetti().ignoresSafeArea().allowsHitTesting(false) }
            VStack(spacing: 16) {
                Text(iWon ? "🏆" : outcome.isDraw ? "🤝" : "🎯").font(.system(size: 56))
                Text(headline).font(.khTitle).multilineTextAlignment(.center)
                if !outcome.summary.isEmpty { Text(outcome.summary).font(.subheadline).foregroundStyle(Theme.text2) }
                VStack(spacing: 8) {
                    ForEach(Array(outcome.ranking.enumerated()), id: \.offset) { i, s in
                        if seats.indices.contains(s) {
                            HStack(spacing: 10) {
                                Text("\(i + 1)").font(.system(.headline, design: .rounded)).frame(width: 22)
                                AvatarView(spec: seats[s].avatar, size: 30)
                                Text(seats[s].name).font(.system(.body, design: .rounded, weight: .semibold))
                                Spacer()
                            }
                        }
                    }
                }
                if canRematch {
                    Button("Play again", action: onRematch).buttonStyle(PrimaryButtonStyle())
                } else {
                    Text("Waiting for the host to start another round…").font(.footnote).foregroundStyle(Theme.text2)
                }
                Button("Leave", action: onLeave).buttonStyle(SecondaryButtonStyle())
            }
            .padding(24)
            .frame(maxWidth: 380)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(24)
            .foregroundStyle(.white)
        }
        .transition(.opacity)
    }
}

struct Confetti: View {
    private struct Piece { var x, speed, size, phase, hue: Double }
    private let pieces: [Piece] = (0 ..< 70).map { i in
        var r = SplitMix64(seed: UInt64(i) &* 7919)
        func f() -> Double { Double(r.next() % 10_000) / 10_000 }
        return Piece(x: f(), speed: 0.18 + f() * 0.3, size: 6 + f() * 8, phase: f(), hue: f())
    }
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                for p in pieces {
                    let y = (p.phase + t * p.speed).truncatingRemainder(dividingBy: 1.2) * size.height - 20
                    let x = p.x * size.width + sin(t * 2 + p.phase * 10) * 18
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(t * 3 + p.phase * 6))
                    c.fill(Path(CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)),
                           with: .color(Color(hue: p.hue, saturation: 0.8, brightness: 1)))
                }
            }
        }
    }
}
