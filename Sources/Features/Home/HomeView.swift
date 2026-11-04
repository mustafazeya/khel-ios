import SwiftUI

extension GameEntry: Hashable {
    static func == (a: GameEntry, b: GameEntry) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct HomeView: View {
    @Environment(Router.self) private var router
    @Environment(Profile.self) private var profile
    @Environment(StatsStore.self) private var stats

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if profile.name == "Player" { nameCard }
                togetherCard
                ForEach([GameOrigin.indian, .board, .arcade], id: \.self) { origin in
                    section(origin)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(Theme.bg)
        .toolbar(.hidden, for: .navigationBar)
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { router.tab = .me } label: { AvatarView(spec: profile.avatar, size: 54, ring: Theme.accent) }
            VStack(alignment: .leading, spacing: 2) {
                Text("Hello, \(profile.name)").font(.khTitle).lineLimit(1).minimumScaleFactor(0.7)
                Text("\(stats.totalWins) wins · \(stats.totalPlayed) games played").font(.subheadline).foregroundStyle(Theme.text2)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var nameCard: some View {
        Button { router.tab = .me } label: {
            Card {
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Make it yours").font(.khHeadline)
                        Text("Set your name and design your avatar. Other players see them.").font(.footnote).foregroundStyle(Theme.text2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.dim)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var togetherCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Play together on Wi-Fi", systemImage: "iphone.gen3.radiowaves.left.and.right").font(.khHeadline)
                Text("One iPhone hosts a room, the other joins. No internet and no accounts.").font(.subheadline).foregroundStyle(Theme.text2)
                HStack(spacing: 10) {
                    Button("Host a room") {
                        let room = RoomSession.host(profile: profile)
                        room.startHosting()
                        router.room = room
                    }.buttonStyle(PrimaryButtonStyle())
                    Button("Join a room") { router.tab = .nearby }.buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private func section(_ origin: GameOrigin) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker(text: origin.rawValue)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(GameCatalog.entries(in: origin)) { entry in
                        Button { router.setupGame = entry } label: { GameCard(info: entry.info, record: stats.record(entry.id)) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
}

struct GameCard: View {
    let info: GameInfo
    let record: GameRecord

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.gradient(info.palette)
            Image(systemName: info.symbol)
                .font(.system(size: 84, weight: .bold))
                .foregroundStyle(.white.opacity(0.22))
                .rotationEffect(.degrees(-12))
                .offset(x: 54, y: -34)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Text(info.title).font(.system(size: 20, weight: .heavy, design: .rounded)).lineLimit(2).minimumScaleFactor(0.8)
                Text(info.tagline).font(.system(size: 12, weight: .medium, design: .rounded)).opacity(0.85).lineLimit(2)
                HStack(spacing: 6) {
                    Label(playersText, systemImage: "person.2.fill")
                    if record.bestScore > 0 { Label("\(record.bestScore)", systemImage: "trophy.fill") }
                    else if record.wins > 0 { Label("\(record.wins)", systemImage: "trophy.fill") }
                }
                .font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.9).padding(.top, 4)
            }
            .foregroundStyle(.white)
            .padding(14)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
        }
        .frame(width: 168, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.color(info.palette.last ?? 0).opacity(0.35), radius: 12, y: 6)
    }

    private var playersText: String {
        info.minPlayers == info.maxPlayers ? "\(info.maxPlayers)" : "\(info.minPlayers)–\(info.maxPlayers)"
    }
}

// MARK: - Setup

struct GameSetupView: View {
    let entry: GameEntry
    @Environment(Router.self) private var router
    @Environment(Profile.self) private var profile
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var players = 2
    @State private var level: AILevel = .medium

    private var info: GameInfo { entry.info }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ZStack(alignment: .bottomLeading) {
                        Theme.gradient(info.palette)
                        Image(systemName: info.symbol).font(.system(size: 120, weight: .bold)).foregroundStyle(.white.opacity(0.2))
                            .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 16)
                        VStack(alignment: .leading) {
                            Text(info.title).font(.khTitle)
                            Text(info.tagline).font(.subheadline).opacity(0.9)
                        }.padding(18)
                    }
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Kicker(text: "How to play")
                            Text(info.rules).font(.callout).foregroundStyle(Theme.text2)
                        }
                    }

                    if info.mode == .solo {
                        Button("Play") { dismiss(); launch(.local, humans: 1, ai: 0) }.buttonStyle(PrimaryButtonStyle())
                    } else {
                        modes
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .onAppear {
                players = max(info.minPlayers, 2)
                level = settings.aiLevel
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var modes: some View {
        if info.maxPlayers > 2 {
            Card {
                Stepper(value: $players, in: max(2, info.minPlayers) ... info.maxPlayers) {
                    Text("Players: \(players)").font(.khHeadline)
                }
            }
        }
        if info.supportsAI {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Kicker(text: "Computer level")
                    Picker("Level", selection: $level) { ForEach(AILevel.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                }
            }
            Button { dismiss(); launch(.local, humans: 1, ai: players - 1) } label: { Label("Play vs computer", systemImage: "cpu") }
                .buttonStyle(PrimaryButtonStyle())
        }
        if info.minPlayers == 1 {
            Button { dismiss(); launch(.local, humans: 1, ai: 0) } label: { Label("Solo practice", systemImage: "person.fill") }
                .buttonStyle(SecondaryButtonStyle())
        }
        if info.mode == .turnBased {
            Button { dismiss(); launch(.local, humans: players, ai: 0) } label: { Label("Pass & play on this iPhone", systemImage: "hand.tap.fill") }
                .buttonStyle(SecondaryButtonStyle())
        }
        if info.isMultiplayer {
            Button {
                dismiss()
                let room = RoomSession.host(profile: profile)
                room.setOptions(RoomOptions(gameID: info.id, aiFill: 0, aiLevel: level))
                room.startHosting()
                router.room = room
            } label: { Label("Host on Wi-Fi (other iPhones join)", systemImage: "wifi") }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func launch(_ role: GameLaunch.Role, humans: Int, ai: Int) {
        var rng = SystemRandomNumberGenerator()
        var botRNG = SplitMix64(seed: rng.next())
        var seats: [SeatConfig] = [profile.seat(index: 0)]
        for i in 1 ..< max(humans, 1) {
            seats.append(SeatConfig(index: i, name: "Player \(i + 1)", avatar: .random(seed: botRNG.next()), kind: .local))
        }
        for _ in 0 ..< ai {
            let bot = BotIdentity.make(index: seats.count, using: &botRNG, avoiding: seats.map(\.name))
            seats.append(SeatConfig(index: seats.count, name: bot.name, avatar: bot.avatar, kind: .ai(level)))
        }
        settings.aiLevel = level
        let mine = Set(seats.filter { $0.kind == .local }.map(\.index))
        let launch = GameLaunch(gameID: info.id, seats: seats, seed: rng.next(), role: role, mySeats: mine)
        // Present after the sheet has finished dismissing.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            router.localGame = ActiveGame(launch: launch)
        }
    }
}
