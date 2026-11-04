import XCTest
@testable import Khel

final class CoreTests: XCTestCase {
    // MARK: Framing

    func testFrameRoundTripAndChunking() throws {
        let p1 = Packet(.action, seat: 1, seq: 7, payload: Data([1, 2, 3]), text: "x")
        let p2 = Packet.make(.state, seq: 9, value: ["a": 1])
        var wire = try FrameCodec.encode(p1)
        wire.append(try FrameCodec.encode(p2))

        var codec = FrameCodec()
        var got: [Packet] = []
        for byte in wire { got += try codec.feed(Data([byte])) }   // worst case: one byte at a time
        XCTAssertEqual(got.count, 2)
        XCTAssertEqual(got[0].kind, .action)
        XCTAssertEqual(got[0].payload, Data([1, 2, 3]))
        XCTAssertEqual(got[1].seq, 9)
        XCTAssertEqual(got[1].decode([String: Int].self), ["a": 1])
    }

    func testFrameRejectsOversizeAndGarbage() {
        var codec = FrameCodec()
        var huge = UInt32(FrameCodec.maxFrame + 1).bigEndian
        XCTAssertThrowsError(try codec.feed(Data(bytes: &huge, count: 4)))

        var codec2 = FrameCodec()
        var len = UInt32(5).bigEndian
        var bad = Data(bytes: &len, count: 4)
        bad.append(Data("notjs".utf8))
        XCTAssertThrowsError(try codec2.feed(bad))
    }

    // MARK: RNG

    func testSplitMixIsDeterministicAndCodable() throws {
        var a = SplitMix64(seed: 42), b = SplitMix64(seed: 42)
        XCTAssertEqual((0 ..< 20).map { _ in a.next() }, (0 ..< 20).map { _ in b.next() })
        let data = try JSONEncoder().encode(a)
        var c = try JSONDecoder().decode(SplitMix64.self, from: data)
        XCTAssertEqual(a.next(), c.next())
        var r = SplitMix64(seed: 1)
        for _ in 0 ..< 1000 { XCTAssertTrue((1 ... 6).contains(r.int(in: 1 ... 6))) }
    }

    // MARK: SVG

    @MainActor func testEveryAvatarOptionProducesValidSVG() throws {
        var specs: [AvatarSpec] = (0 ..< 300).map { AvatarSpec.random(seed: UInt64($0)) }
        // Sweep each field through its whole range, so every drawing branch runs.
        for i in 0 ..< 8 {
            var s = AvatarSpec()
            s.face = i; s.hair = i; s.eyes = i; s.mouth = i; s.facialHair = i; s.headwear = i; s.glasses = i; s.clothing = i
            s.skin = i; s.hairColor = i; s.clothingColor = i; s.background = i; s.backgroundColor = i; s.extras = i
            specs.append(s)
        }
        for spec in specs {
            let svg = AvatarSVG.document(spec)
            let doc = try XCTUnwrap(SVGDocument(string: svg), "invalid SVG for \(spec)")
            XCTAssertEqual(doc.viewBox.width, 200)
            XCTAssertNotNil(AvatarCache.document(spec))
        }
    }

    func testAvatarClampingSurvivesGarbage() {
        let s = AvatarSpec(skin: 99, face: -4, hair: 1000, hairColor: 77, brows: 9, eyes: 9, mouth: 9, facialHair: 9, headwear: 9,
                           glasses: 9, clothing: 9, clothingColor: 99, background: 9, backgroundColor: 99, extras: 255)
        XCTAssertNotNil(SVGDocument(string: AvatarSVG.document(s)))
    }

    func testAvatarSpecJSONRoundTrip() throws {
        let s = AvatarSpec.random(seed: 5)
        XCTAssertEqual(try JSONDecoder().decode(AvatarSpec.self, from: JSONEncoder().encode(s)), s)
    }

    func testPathParserHandlesAllCommands() {
        let rect = SVGPathParser.parse("M10 10 H90 V90 H10 Z").boundingRect
        XCTAssertEqual(rect, CGRect(x: 10, y: 10, width: 80, height: 80))

        let rel = SVGPathParser.parse("m10,10 l20,0 l0,20 z").boundingRect
        XCTAssertEqual(rel, CGRect(x: 10, y: 10, width: 20, height: 20))

        // Half-circle arc of radius 50 from (0,50) to (100,50): top of the arc is at y = 0.
        let arc = SVGPathParser.parse("M0 50 A50 50 0 0 1 100 50").boundingRect
        XCTAssertEqual(arc.minY, 0, accuracy: 0.5)
        XCTAssertEqual(arc.width, 100, accuracy: 0.5)

        // Compact numbers and implicit repeats.
        let compact = SVGPathParser.parse("M0 0L10-5 20 5").boundingRect
        XCTAssertEqual(compact.width, 20)

        XCTAssertTrue(SVGPathParser.parse("").isEmpty)
        XCTAssertTrue(SVGPathParser.parse("garbage").isEmpty)
    }

    func testSVGParserRejectsNonSVG() {
        XCTAssertNil(SVGDocument(string: "<html></html>"))
        XCTAssertNil(SVGDocument(string: "not xml"))
        XCTAssertNotNil(SVGDocument(string: #"<svg viewBox="0 0 10 10"><rect width="5" height="5" style="fill:#f00"/></svg>"#))
    }

    func testColorParsing() {
        XCTAssertNotNil(SVGColor.parse("#FFF"))
        XCTAssertNotNil(SVGColor.parse("#112233"))
        XCTAssertNotNil(SVGColor.parse("#11223344"))
        XCTAssertNil(SVGColor.parse("#12"))
        XCTAssertEqual(AvatarSVG.mix("#000000", with: "#FFFFFF", 0.5), "#808080")
    }

    // MARK: Catalog

    @MainActor func testCatalogIsConsistent() {
        var ids = Set<String>()
        for e in GameCatalog.all {
            XCTAssertTrue(ids.insert(e.id).inserted, "duplicate id \(e.id)")
            XCTAssertLessThanOrEqual(e.info.minPlayers, e.info.maxPlayers)
            XCTAssertEqual(e.info.palette.count, 2)
            XCTAssertFalse(e.info.rules.isEmpty)
            XCTAssertNotEqual(e.info.rules, "TODO", "\(e.id) still has placeholder rules")
            if e.info.mode == .solo { XCTAssertEqual(e.info.maxPlayers, 1) }
        }
        XCTAssertGreaterThanOrEqual(GameCatalog.all.count, 19)
    }

    // MARK: Stats

    @MainActor func testStatsRecording() {
        let stats = StatsStore.shared
        let id = "test-game-\(UUID().uuidString)"
        stats.record(gameID: id, outcome: .win(0, others: [1]), mySeats: [0], seatCount: 2)
        stats.record(gameID: id, outcome: .win(1, others: [0]), mySeats: [0], seatCount: 2)
        stats.record(gameID: id, outcome: .draw(), mySeats: [0], seatCount: 2)
        let r = stats.record(id)
        XCTAssertEqual(r.played, 3); XCTAssertEqual(r.wins, 1); XCTAssertEqual(r.draws, 1); XCTAssertEqual(r.losses, 1)
    }
}
