import Foundation

/// One message on the wire. Packets are JSON, framed with a 4-byte big-endian length prefix.
struct Packet: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case hello, welcome, reject, roster, options, start, end
        case action, state, seats, rt, sync
        case emote, ping, pong, leave
    }

    var kind: Kind
    /// Seat the packet refers to (action sender, rt sender...).
    var seat: Int?
    /// Monotonic game-state version.
    var seq: UInt64?
    var payload: Data?
    /// Secondary payload (for `state`: the action that produced it).
    var aux: Data?
    var text: String?

    init(_ kind: Kind, seat: Int? = nil, seq: UInt64? = nil, payload: Data? = nil, aux: Data? = nil, text: String? = nil) {
        self.kind = kind; self.seat = seat; self.seq = seq; self.payload = payload; self.aux = aux; self.text = text
    }

    func decode<T: Decodable>(_ type: T.Type = T.self) -> T? {
        guard let payload else { return nil }
        return try? JSONDecoder().decode(T.self, from: payload)
    }

    static func make<T: Encodable>(_ kind: Kind, seat: Int? = nil, seq: UInt64? = nil, value: T, aux: (any Encodable)? = nil, text: String? = nil) -> Packet {
        Packet(kind, seat: seat, seq: seq,
               payload: try? JSONEncoder().encode(value),
               aux: aux.flatMap { try? JSONEncoder().encode(AnyEncodable($0)) },
               text: text)
    }
}

struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

/// Length-prefixed framing. Pure and synchronous so it can be unit-tested without sockets.
struct FrameCodec: Sendable {
    /// Frames larger than this are treated as a protocol violation (protects the host from garbage / abuse).
    static let maxFrame = 1 << 20

    enum Failure: Error { case oversize(Int), malformed }

    static func encode(_ packet: Packet) throws -> Data {
        let body = try JSONEncoder().encode(packet)
        guard body.count <= maxFrame else { throw Failure.oversize(body.count) }
        var length = UInt32(body.count).bigEndian
        var out = Data(bytes: &length, count: 4)
        out.append(body)
        return out
    }

    private var buffer = Data()

    /// Append received bytes and return every complete packet.
    mutating func feed(_ data: Data) throws -> [Packet] {
        buffer.append(data)
        var packets: [Packet] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard length <= Self.maxFrame else { throw Failure.oversize(length) }
            guard buffer.count >= 4 + length else { break }
            let body = buffer.subdata(in: buffer.startIndex + 4 ..< buffer.startIndex + 4 + length)
            buffer = Data(buffer.dropFirst(4 + length))
            guard let packet = try? JSONDecoder().decode(Packet.self, from: body) else { throw Failure.malformed }
            packets.append(packet)
        }
        return packets
    }
}

/// Entry in the lobby roster.
struct RosterEntry: Codable, Sendable, Hashable, Identifiable {
    var playerID: UUID
    var name: String
    var avatar: AvatarSpec
    var connected: Bool = true
    var isHost: Bool = false
    var id: UUID { playerID }
}

struct Hello: Codable, Sendable {
    var version: Int
    var playerID: UUID
    var name: String
    var avatar: AvatarSpec
}

struct Welcome: Codable, Sendable {
    var playerID: UUID
    var roomName: String
}

struct RoomOptions: Codable, Sendable, Equatable {
    var gameID: String?
    var aiFill: Int = 0
    var aiLevel: AILevel = .medium
    var options: [String: String] = [:]
}

enum Wire {
    static let version = 1
    static let serviceType = "_khel._tcp"
}
