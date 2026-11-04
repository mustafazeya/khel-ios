import SwiftUI
import Network

/// Find rooms on the network or join by address.
struct NearbyView: View {
    @Environment(Router.self) private var router
    @Environment(Profile.self) private var profile
    @State private var browser = RoomBrowser()
    @State private var address = ""
    @State private var showManual = false

    var body: some View {
        List {
            Section {
                if browser.rooms.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Looking for rooms…").font(.headline)
                            Text("Ask the other player to tap “Host a room”. Both iPhones need the same Wi-Fi (or a hotspot).")
                                .font(.footnote).foregroundStyle(Theme.text2)
                        }
                    }
                }
                ForEach(browser.rooms) { room in
                    Button { join(endpoint: room.endpoint) } label: {
                        HStack {
                            Image(systemName: GameCatalog.info(room.gameID)?.symbol ?? "wifi").frame(width: 32).foregroundStyle(Theme.accent)
                            VStack(alignment: .leading) {
                                Text(room.name).font(.headline)
                                Text(GameCatalog.info(room.gameID)?.title ?? "Choosing a game").font(.footnote).foregroundStyle(Theme.text2)
                            }
                            Spacer()
                            Text("\(room.players)/\(room.maxPlayers)").font(.footnote.monospacedDigit()).foregroundStyle(Theme.text2)
                        }
                    }
                }
                if let f = browser.failure {
                    Label(f, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.bad)
                }
            } header: { Text("Rooms on this network") }

            Section {
                DisclosureGroup("Join by address", isExpanded: $showManual) {
                    TextField("192.168.1.20:51234", text: $address)
                        .keyboardType(.numbersAndPunctuation).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button("Connect") { joinManual() }.disabled(parsedAddress == nil)
                }
            } footer: { Text("Use this if the room does not show up. The host's address is shown in their lobby.") }

            Section {
                Button { host() } label: { Label("Host a room", systemImage: "plus.circle.fill") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Nearby")
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
    }

    private var parsedAddress: (String, UInt16)? {
        let parts = address.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let port = UInt16(parts[1]), !parts[0].isEmpty else { return nil }
        return (String(parts[0]), port)
    }

    private func host() {
        let room = RoomSession.host(profile: profile)
        room.startHosting()
        router.room = room
    }

    private func join(endpoint: NWEndpoint) {
        let room = RoomSession.client(profile: profile)
        room.connect(to: endpoint)
        router.room = room
    }

    private func joinManual() {
        guard let (h, p) = parsedAddress else { return }
        let room = RoomSession.client(profile: profile)
        room.connect(host: h, port: p)
        router.room = room
    }
}

/// The waiting room, for the host and for joined players. Shows the game when the host starts it.
struct LobbyView: View {
    let room: RoomSession
    @Environment(Router.self) private var router
    @Environment(AppSettings.self) private var settings
    @State private var closedReason: String?

    private var options: RoomOptions { room.options }
    private var info: GameInfo? { options.gameID.flatMap(GameCatalog.info) }
    private var humans: Int { room.roster.filter(\.connected).count }
    private var canStart: Bool {
        guard let info else { return false }
        return humans + options.aiFill >= info.minPlayers && humans <= info.maxPlayers && room.phase == .lobby
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusCard
                    gameCard
                    playersCard
                    if room.role == .host { addressCard }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle(room.roomName.isEmpty ? "Room" : room.roomName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Leave", role: .destructive) { router.leaveRoom() } }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .fullScreenCover(isPresented: Binding(get: { room.phase == .playing }, set: { _ in })) {
            if let launch = room.launch {
                GameContainer(launch: launch, room: room) {
                    if room.role == .host { room.endGame() } else { router.leaveRoom() }
                }
            }
        }
        .onChange(of: room.phase) { _, phase in
            if case .closed(let reason) = phase { closedReason = reason }
        }
        .alert("Disconnected", isPresented: Binding(get: { closedReason != nil && router.room != nil }, set: { _ in })) {
            Button("OK") { closedReason = nil; router.room = nil }
        } message: { Text(closedReason ?? "") }
        .preferredColorScheme(.dark)
    }

    private var statusCard: some View {
        Card {
            HStack(spacing: 12) {
                if room.phase == .connecting || room.reconnecting { ProgressView() }
                else { Image(systemName: "wifi").foregroundStyle(Theme.good) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.reconnecting ? "Reconnecting…" : room.phase == .connecting ? "Connecting…" :
                            room.role == .host ? "You're hosting" : "Connected").font(.khHeadline)
                    if let ms = room.latencyMs, room.role == .client { Text("Latency \(ms) ms").font(.footnote).foregroundStyle(Theme.text2) }
                }
                Spacer()
            }
        }
    }

    private var gameCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Kicker(text: "Game")
                if room.role == .host {
                    Menu {
                        ForEach(GameCatalog.multiplayer) { e in
                            Button { var o = options; o.gameID = e.id; room.setOptions(o) } label: { Label(e.info.title, systemImage: e.info.symbol) }
                        }
                    } label: {
                        HStack {
                            Label(info?.title ?? "Choose a game", systemImage: info?.symbol ?? "gamecontroller").font(.khHeadline)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.footnote)
                        }
                    }
                } else {
                    Label(info?.title ?? "The host is choosing a game…", systemImage: info?.symbol ?? "hourglass").font(.khHeadline)
                }
                if let info, room.role == .host, info.supportsAI {
                    Stepper(value: Binding(get: { options.aiFill }, set: { var o = options; o.aiFill = $0; room.setOptions(o) }),
                            in: 0 ... max(0, info.maxPlayers - 1)) {
                        Text(options.aiFill == 0 ? "No computer players" : "\(options.aiFill) computer player\(options.aiFill == 1 ? "" : "s")")
                    }
                    Picker("Level", selection: Binding(get: { options.aiLevel }, set: { var o = options; o.aiLevel = $0; room.setOptions(o) })) {
                        ForEach(AILevel.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                }
                if let info { Text("\(info.minPlayers == info.maxPlayers ? "\(info.maxPlayers)" : "\(info.minPlayers)–\(info.maxPlayers)") players").font(.footnote).foregroundStyle(Theme.text2) }
            }
        }
    }

    private var playersCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Kicker(text: "Players (\(room.roster.count))")
                ForEach(room.roster) { p in
                    HStack(spacing: 12) {
                        AvatarView(spec: p.avatar, size: 42)
                        VStack(alignment: .leading) {
                            Text(p.name).font(.headline)
                            if p.isHost { Text("Host").font(.caption).foregroundStyle(Theme.accent) }
                        }
                        Spacer()
                        if !p.connected { Label("Away", systemImage: "wifi.slash").font(.caption).foregroundStyle(Theme.bad) }
                    }
                }
                if room.roster.isEmpty { Text("Waiting for the host…").foregroundStyle(Theme.text2) }
            }
        }
    }

    private var addressCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: "Can't see the room?")
                if let port = room.port, !room.addresses.isEmpty {
                    Text(room.addresses.map { "\($0):\(port)" }.joined(separator: "   ")).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Text("Type this in Nearby › Join by address.").font(.footnote).foregroundStyle(Theme.text2)
                } else {
                    Text("Connect both iPhones to the same Wi-Fi.").font(.footnote).foregroundStyle(Theme.text2)
                }
            }
        }
    }

    @ViewBuilder private var bottomBar: some View {
        if room.role == .host {
            Button { room.startGame() } label: { Text(info == nil ? "Choose a game" : humans + options.aiFill < (info?.minPlayers ?? 2) ? "Waiting for players…" : "Start game") }
                .buttonStyle(PrimaryButtonStyle()).disabled(!canStart)
                .padding(.horizontal, 16).padding(.bottom, 8).padding(.top, 8)
                .background(.ultraThinMaterial)
        }
    }
}
