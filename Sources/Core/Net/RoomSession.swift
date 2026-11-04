import Foundation
import Network
import Observation

struct Emote: Identifiable, Equatable, Sendable {
    let id = UUID()
    let from: String
    let seat: Int?
    let emoji: String
}

/// A multiplayer room. The host iPhone *is* the local server: it advertises over Bonjour, accepts TCP
/// connections from other iPhones, owns the roster and is the authority for every game it starts.
/// A client is the same object in `.client` role, connected to a host.
@MainActor @Observable
final class RoomSession {
    enum Role: Sendable { case host, client }
    enum Phase: Equatable, Sendable { case connecting, lobby, playing, closed(String) }

    let role: Role
    let me: RosterEntry
    private(set) var roomName: String
    private(set) var roster: [RosterEntry]
    private(set) var options = RoomOptions()
    private(set) var phase: Phase = .connecting
    private(set) var launch: GameLaunch?
    private(set) var port: UInt16?
    private(set) var addresses: [String] = []
    private(set) var latencyMs: Int?
    private(set) var lastEmote: Emote?
    private(set) var reconnecting = false

    /// Game-level packets (`action`, `state`, `seats`, `rt`) are delivered here with the sender's player id (host side).
    @ObservationIgnored var onGamePacket: ((Packet, UUID?) -> Void)?
    /// Host side: a player who was away has come back and needs the current game state.
    @ObservationIgnored var onPeerRejoined: ((UUID) -> Void)?
    /// Host side: a player's connection state changed during a game.
    @ObservationIgnored var onPeerPresence: ((UUID, Bool) -> Void)?

    // Host
    private var listener: NWListener?
    private final class Peer: @unchecked Sendable { let conn: FramedConnection; var playerID: UUID?; var lastSeen = Date(); init(_ c: FramedConnection) { conn = c } }
    private var peers: [ObjectIdentifier: Peer] = [:]

    // Client
    private var endpoint: NWEndpoint?
    private var conn: FramedConnection?
    private var lastHostPacket = Date()
    private var leaving = false

    private var heartbeat: Task<Void, Never>?

    // MARK: Creation

    static func host(profile: Profile, roomName: String? = nil) -> RoomSession {
        host(entry: profile.rosterEntry(isHost: true), roomName: roomName)
    }

    static func client(profile: Profile) -> RoomSession {
        client(entry: profile.rosterEntry(isHost: false))
    }

    static func host(entry: RosterEntry, roomName: String? = nil) -> RoomSession {
        var me = entry
        me.isHost = true
        return RoomSession(role: .host, me: me, roomName: roomName ?? "\(entry.name)'s room")
    }

    static func client(entry: RosterEntry) -> RoomSession {
        var me = entry
        me.isHost = false
        return RoomSession(role: .client, me: me, roomName: "")
    }

    private init(role: Role, me: RosterEntry, roomName: String) {
        self.role = role
        self.me = me
        self.roomName = roomName
        self.roster = role == .host ? [me] : []
    }

    // MARK: Host lifecycle

    func startHosting() {
        guard role == .host else { return }
        do {
            let listener = try NWListener(using: FramedConnection.parameters())
            listener.newConnectionHandler = { [weak self] connection in
                let framed = FramedConnection(connection: connection, label: "khel.peer")
                Task { @MainActor in self?.accept(framed) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.port = listener.port?.rawValue
                        self.addresses = NetworkInfo.localAddresses()
                        if self.phase == .connecting { self.phase = .lobby }
                    case .failed(let e): self.phase = .closed("Could not host: \(e.localizedDescription)")
                    default: break
                    }
                }
            }
            self.listener = listener
            publishService()
            listener.start(queue: .main)
            startHeartbeat()
        } catch {
            phase = .closed("Could not host: \(error.localizedDescription)")
        }
    }

    private func publishService() {
        guard let listener else { return }
        var txt = NWTXTRecord()
        txt["v"] = String(Wire.version)
        txt["host"] = me.name
        txt["game"] = options.gameID ?? ""
        txt["players"] = String(roster.filter(\.connected).count)
        txt["max"] = String(maxHumans)
        listener.service = NWListener.Service(name: roomName, type: Wire.serviceType, txtRecord: txt)
    }

    private var maxHumans: Int {
        guard let id = options.gameID, let info = GameCatalog.info(id) else { return 6 }
        return info.mode == .solo ? 1 : info.maxPlayers
    }

    private func accept(_ framed: FramedConnection) {
        let peer = Peer(framed)
        let key = ObjectIdentifier(peer)
        peers[key] = peer
        framed.onPacket = { [weak self, weak peer] packet in
            Task { @MainActor in if let self, let peer { self.hostReceive(packet, from: peer) } }
        }
        framed.onStatus = { [weak self, weak peer] status in
            if case .ready = status { return }
            Task { @MainActor in if let self, let peer { self.peerDropped(peer) } }
        }
        framed.start()
    }

    private func hostReceive(_ packet: Packet, from peer: Peer) {
        peer.lastSeen = Date()
        switch packet.kind {
        case .hello:
            guard let hello: Hello = packet.decode() else { return }
            hostAdmit(hello, peer: peer)
        case .ping:
            peer.conn.send(Packet(.pong, seq: packet.seq))
        case .pong:
            break
        case .leave:
            if let id = peer.playerID { removePlayer(id, voluntary: true) }
            peer.conn.cancel()
            peers[ObjectIdentifier(peer)] = nil
        case .emote:
            guard let id = peer.playerID, let name = roster.first(where: { $0.playerID == id })?.name else { return }
            let relay = Packet(.emote, seat: packet.seat, text: packet.text)
            broadcast(relay)
            publishEmote(from: name, seat: packet.seat, emoji: packet.text ?? "")
        case .action, .state, .seats, .rt, .sync:
            guard peer.playerID != nil else { return }
            onGamePacket?(packet, peer.playerID)
        default:
            break
        }
    }

    private func hostAdmit(_ hello: Hello, peer: Peer) {
        guard hello.version == Wire.version else {
            peer.conn.sendAndClose(Packet(.reject, text: "Update Khel on both iPhones to the same version."))
            return
        }
        let name = String(hello.name.prefix(24))
        if let i = roster.firstIndex(where: { $0.playerID == hello.playerID }) {
            // Rejoin: swap the connection.
            for (k, p) in peers where p.playerID == hello.playerID && p !== peer { p.conn.cancel(); peers[k] = nil }
            roster[i].connected = true
            roster[i].name = name
            roster[i].avatar = hello.avatar
        } else {
            guard phase == .lobby else { peer.conn.sendAndClose(Packet(.reject, text: "A game is already in progress.")); return }
            guard roster.count < maxHumans else { peer.conn.sendAndClose(Packet(.reject, text: "The room is full.")); return }
            roster.append(RosterEntry(playerID: hello.playerID, name: name, avatar: hello.avatar))
        }
        peer.playerID = hello.playerID
        peer.conn.send(.make(.welcome, value: Welcome(playerID: hello.playerID, roomName: roomName)))
        peer.conn.send(.make(.options, value: options))
        broadcastRoster()
        publishService()
        if phase == .playing, let launch {
            peer.conn.send(.make(.start, value: launchFor(playerID: hello.playerID, base: launch)))
            onPeerRejoined?(hello.playerID)
            onPeerPresence?(hello.playerID, true)
        }
    }

    private func peerDropped(_ peer: Peer) {
        peers[ObjectIdentifier(peer)] = nil
        guard let id = peer.playerID else { return }
        // A newer connection for the same player may already have replaced this one.
        if peers.values.contains(where: { $0.playerID == id }) { return }
        removePlayer(id, voluntary: false)
    }

    private func removePlayer(_ id: UUID, voluntary: Bool) {
        guard let i = roster.firstIndex(where: { $0.playerID == id }), !roster[i].isHost else { return }
        if phase == .playing {
            roster[i].connected = false
            onPeerPresence?(id, false)
        } else {
            roster.remove(at: i)
        }
        broadcastRoster()
        publishService()
    }

    private func broadcastRoster() { broadcast(.make(.roster, value: roster)) }

    /// Send to every connected client.
    func broadcast(_ packet: Packet) {
        guard role == .host else { return }
        for p in peers.values where p.playerID != nil { p.conn.send(packet) }
    }

    func send(_ packet: Packet, to playerID: UUID) {
        guard role == .host else { return }
        for p in peers.values where p.playerID == playerID { p.conn.send(packet) }
    }

    /// Client → host.
    func sendToHost(_ packet: Packet) {
        guard role == .client else { return }
        conn?.send(packet)
    }

    // MARK: Host game control

    func setOptions(_ new: RoomOptions) {
        guard role == .host else { return }
        options = new
        broadcast(.make(.options, value: options))
        publishService()
    }

    /// Build seats from the roster (+ AI fill) and start the selected game for everyone.
    @discardableResult
    func startGame() -> GameLaunch? {
        guard role == .host, phase == .lobby, let gameID = options.gameID, let info = GameCatalog.info(gameID) else { return nil }
        let humans = roster.filter(\.connected)
        var seats: [SeatConfig] = []
        for (i, h) in humans.enumerated() {
            seats.append(SeatConfig(index: i, name: h.name, avatar: h.avatar, kind: h.isHost ? .local : .remote(h.playerID)))
        }
        let want = min(info.maxPlayers, max(humans.count + options.aiFill, info.minPlayers))
        var seed = SystemRandomNumberGenerator()
        var botRNG = SplitMix64(seed: seed.next())
        while seats.count < want {
            let bot = BotIdentity.make(index: seats.count, using: &botRNG, avoiding: seats.map(\.name))
            seats.append(SeatConfig(index: seats.count, name: bot.name, avatar: bot.avatar, kind: .ai(options.aiLevel)))
        }
        let launch = GameLaunch(gameID: gameID, seats: seats, seed: seed.next(), role: .host,
                                mySeats: Set(seats.filter { $0.kind == .local }.map(\.index)), options: options.options)
        self.launch = launch
        phase = .playing
        for h in humans where !h.isHost {
            send(.make(.start, value: launchFor(playerID: h.playerID, base: launch)), to: h.playerID)
        }
        return launch
    }

    private func launchFor(playerID: UUID, base: GameLaunch) -> GameLaunch {
        var l = base
        l.role = .client
        l.mySeats = Set(base.seats.filter { $0.kind == .remote(playerID) }.map(\.index))
        return l
    }

    /// Host: return everyone to the lobby.
    func endGame() {
        guard role == .host else { return }
        launch = nil
        phase = .lobby
        roster.removeAll { !$0.connected && !$0.isHost }
        broadcast(Packet(.end))
        broadcastRoster()
        publishService()
    }

    // MARK: Emotes

    func sendEmote(_ emoji: String, seat: Int?) {
        publishEmote(from: me.name, seat: seat, emoji: emoji)
        let packet = Packet(.emote, seat: seat, text: emoji)
        if role == .host { broadcast(packet) } else { sendToHost(packet) }
    }

    private func publishEmote(from: String, seat: Int?, emoji: String) {
        lastEmote = Emote(from: from, seat: seat, emoji: emoji)
    }

    // MARK: Client lifecycle

    func connect(to endpoint: NWEndpoint) {
        guard role == .client else { return }
        self.endpoint = endpoint
        leaving = false
        phase = .connecting
        openConnection()
        startHeartbeat()
    }

    func connect(host: String, port: UInt16) {
        guard let p = NWEndpoint.Port(rawValue: port) else { phase = .closed("Invalid port"); return }
        connect(to: .hostPort(host: NWEndpoint.Host(host), port: p))
    }

    private func openConnection() {
        guard let endpoint else { return }
        conn?.cancel()
        let framed = FramedConnection(connection: NWConnection(to: endpoint, using: FramedConnection.parameters()), label: "khel.client")
        framed.onPacket = { [weak self] packet in Task { @MainActor in self?.clientReceive(packet) } }
        framed.onStatus = { [weak self, weak framed] status in
            switch status {
            case .ready:
                Task { @MainActor in
                    guard let self, let framed, self.conn === framed else { return }
                    self.lastHostPacket = Date()
                    framed.send(.make(.hello, value: Hello(version: Wire.version, playerID: self.me.playerID, name: self.me.name, avatar: self.me.avatar)))
                }
            case .failed, .closed:
                Task { @MainActor in
                    guard let self, let framed, self.conn === framed else { return }
                    self.connectionLost()
                }
            }
        }
        conn = framed
        framed.start()
    }

    private func clientReceive(_ packet: Packet) {
        lastHostPacket = Date()
        switch packet.kind {
        case .welcome:
            reconnecting = false
            if let w: Welcome = packet.decode() { roomName = w.roomName }
            if phase == .connecting { phase = launch == nil ? .lobby : .playing }
        case .reject:
            leaving = true
            phase = .closed(packet.text ?? "The host refused the connection.")
            conn?.cancel()
        case .roster:
            if let r: [RosterEntry] = packet.decode() { roster = r }
        case .options:
            if let o: RoomOptions = packet.decode() { options = o }
        case .start:
            if let l: GameLaunch = packet.decode() { launch = l; phase = .playing }
        case .end:
            launch = nil
            if phase == .playing { phase = .lobby }
        case .ping:
            conn?.send(Packet(.pong, seq: packet.seq))
        case .pong:
            if let sent = packet.seq { latencyMs = max(0, Int(Date().timeIntervalSince1970 * 1000) - Int(sent)) }
        case .emote:
            let from = launch?.seats.first(where: { $0.index == packet.seat })?.name ?? "Player"
            publishEmote(from: from, seat: packet.seat, emoji: packet.text ?? "")
        case .state, .action, .seats, .rt:
            onGamePacket?(packet, nil)
        case .sync:
            break
        case .hello, .leave:
            break
        }
    }

    private func connectionLost() {
        guard role == .client, !leaving else { return }
        if case .closed = phase { return }
        reconnecting = true
        Task { @MainActor [weak self] in
            for attempt in 1 ... 6 {
                try? await Task.sleep(for: .seconds(min(2.0 * Double(attempt), 6)))
                guard let self, !self.leaving, self.reconnecting else { return }
                self.openConnection()
                try? await Task.sleep(for: .seconds(3))
                if !self.reconnecting { return }
            }
            guard let self, self.reconnecting else { return }
            self.reconnecting = false
            self.phase = .closed("Lost connection to the host.")
        }
    }

    // MARK: Heartbeat

    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        let stamp = UInt64(Date().timeIntervalSince1970 * 1000)
        switch role {
        case .host:
            let now = Date()
            for (key, peer) in peers {
                if now.timeIntervalSince(peer.lastSeen) > 9 {
                    peer.conn.cancel(); peers[key] = nil
                    if let id = peer.playerID, !peers.values.contains(where: { $0.playerID == id }) { removePlayer(id, voluntary: false) }
                } else {
                    peer.conn.send(Packet(.ping, seq: stamp))
                }
            }
        case .client:
            guard !reconnecting, phase != .connecting else { return }
            if Date().timeIntervalSince(lastHostPacket) > 9 { conn?.cancel(); connectionLost(); return }
            conn?.send(Packet(.ping, seq: stamp))
        }
    }

    // MARK: Teardown

    func leave() {
        leaving = true
        reconnecting = false
        heartbeat?.cancel()
        switch role {
        case .host:
            listener?.cancel()
            for p in peers.values { p.conn.sendAndClose(Packet(.reject, text: "The host closed the room.")) }
            peers.removeAll()
        case .client:
            conn?.send(Packet(.leave))
            conn?.cancel()
        }
        phase = .closed("Left the room")
    }
}

/// Names and avatars for AI players.
enum BotIdentity {
    static let names = ["Aarav", "Diya", "Kabir", "Meera", "Rohan", "Anaya", "Vikram", "Ishaan", "Tara", "Neel", "Zoya", "Arjun",
                        "Sana", "Dev", "Riya", "Kiran"]

    static func make(index: Int, using rng: inout SplitMix64, avoiding taken: [String]) -> (name: String, avatar: AvatarSpec) {
        let pool = names.filter { !taken.contains($0) }
        let name = pool.isEmpty ? "Bot \(index + 1)" : pool[rng.int(in: 0 ... pool.count - 1)]
        return (name, AvatarSpec.random(seed: rng.next()))
    }
}
