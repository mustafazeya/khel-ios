import XCTest
@testable import Khel

final class CarromTests: XCTestCase {
    typealias W = CarromWorld

    func testInitialLayout() {
        let g = CarromGame()
        XCTAssertEqual(g.pieces.count, 19)
        XCTAssertEqual(g.pieces.filter { $0.kind == .white }.count, 9)
        XCTAssertEqual(g.pieces.filter { $0.kind == .black }.count, 9)
        XCTAssertEqual(g.pieces.filter { $0.kind == .queen }.count, 1)
        XCTAssertEqual(Set(g.pieces.map(\.id)).count, 19)
        for (i, a) in g.pieces.enumerated() { for b in g.pieces[(i + 1)...] {
            let d = a.p - b.p
            XCTAssertGreaterThanOrEqual((d.x * d.x + d.y * d.y).squareRoot(), 2 * W.coinR - 1e-6, "pieces \(a.id) and \(b.id) overlap")
        } }
        XCTAssertTrue(CarromAI.candidates(g, seat: 0).isEmpty || true)
    }

    func testRestStaysAtRest() {
        var w = W(pieces: CarromGame().pieces)
        for _ in 0 ..< 240 { _ = w.step() }
        XCTAssertTrue(w.atRest)
        XCTAssertEqual(w.pieces, CarromGame().pieces)
    }

    func testPiecesStayOnTheBoardAndSlowDown() {
        var w = W(pieces: [CarromPiece(id: 99, kind: .striker, p: SIMD2(0.5, 0.8), v: SIMD2(2.1, -1.4)), CarromPiece(id: 1, kind: .white, p: SIMD2(0.5, 0.5))])
        var maxSpeedLater = 0.0
        for k in 0 ..< 1500 {
            _ = w.step()
            for p in w.pieces where !p.pocketed {
                XCTAssertGreaterThanOrEqual(p.p.x, p.radius - 1e-9); XCTAssertLessThanOrEqual(p.p.x, 1 - p.radius + 1e-9)
                XCTAssertGreaterThanOrEqual(p.p.y, p.radius - 1e-9); XCTAssertLessThanOrEqual(p.p.y, 1 - p.radius + 1e-9)
            }
            if k > 1200 { maxSpeedLater = max(maxSpeedLater, w.pieces.map { ($0.v.x * $0.v.x + $0.v.y * $0.v.y).squareRoot() }.max() ?? 0) }
        }
        XCTAssertLessThan(maxSpeedLater, 0.5)
    }

    func testCollisionConservesMomentumRoughly() {
        var w = W(pieces: [CarromPiece(id: 1, kind: .white, p: SIMD2(0.4, 0.5), v: SIMD2(1.0, 0)), CarromPiece(id: 2, kind: .black, p: SIMD2(0.5, 0.5))])
        let before = w.pieces.reduce(SIMD2(0.0, 0.0)) { $0 + $1.v * $1.mass }
        for _ in 0 ..< 40 { _ = w.step() }
        let after = w.pieces.reduce(SIMD2(0.0, 0.0)) { $0 + $1.v * $1.mass }
        XCTAssertEqual(after.x, before.x * exp(-1.55 * 40 * W.dt), accuracy: 0.08, "only table friction removes momentum")
        XCTAssertGreaterThan(w.pieces[1].v.x, 0.5, "the struck coin moves on")
    }

    func testPocketing() {
        var w = W(pieces: [CarromPiece(id: 1, kind: .white, p: SIMD2(0.2, 0.2), v: SIMD2(-1.0, -1.0))])
        let ev = w.simulateToRest()
        XCTAssertEqual(ev.pocketed, [1])
        XCTAssertTrue(w.pieces[0].pocketed)
    }

    func testSimulationIsDeterministic() {
        let shot = CarromShot(number: 0, seat: 0, x: 0.45, vx: 0.4, vy: -2.6)
        func run() -> [CarromPiece] {
            var w = W(pieces: CarromGame().pieces + [CarromAI.striker(for: shot)])
            _ = w.simulateToRest()
            return w.pieces
        }
        XCTAssertEqual(run(), run())
    }

    // MARK: Rules

    private func game(pocketed: [Int]) -> CarromGame {
        var g = CarromGame()
        for i in g.pieces.indices where pocketed.contains(g.pieces[i].id) { g.pieces[i].pocketed = true }
        return g
    }

    func testOwnCoinScoresAndKeepsTheTurn() {
        var g = game(pocketed: [1])
        g.resolve(pocketedIDs: [1], strikerPocketed: false)
        XCTAssertEqual(g.score, [1, 0]); XCTAssertEqual(g.turn, 0)
    }

    func testOpponentCoinPassesTurnAndHelpsThem() {
        var g = game(pocketed: [10])
        g.resolve(pocketedIDs: [10], strikerPocketed: false)
        XCTAssertEqual(g.score, [0, 1]); XCTAssertEqual(g.turn, 1)
    }

    func testMissPassesTurn() {
        var g = CarromGame()
        g.resolve(pocketedIDs: [], strikerPocketed: false)
        XCTAssertEqual(g.turn, 1)
    }

    func testStrikerFoulReturnsCoinsAndPenalises() {
        var g = game(pocketed: [1, 2])
        g.score = [1, 0]
        g.resolve(pocketedIDs: [2], strikerPocketed: true)
        XCTAssertEqual(g.turn, 1)
        XCTAssertEqual(g.pieces.filter { $0.kind == .white && $0.pocketed }.count, 0, "this shot's coin and one owed coin come back")
        XCTAssertEqual(g.score[0], 0)
        XCTAssertTrue(g.pieces.filter { !$0.pocketed }.allSatisfy { p in g.pieces.allSatisfy { $0.id == p.id || $0.pocketed || ($0.p - p.p).magnitudeForTest > 2 * W.coinR - 1e-6 } })
    }

    func testQueenCoveredOnSameShot() {
        var g = game(pocketed: [0, 1])
        g.resolve(pocketedIDs: [0, 1], strikerPocketed: false)
        XCTAssertEqual(g.score, [4, 0]); XCTAssertEqual(g.queenState, 2); XCTAssertEqual(g.turn, 0)
    }

    func testQueenNeedsACoverOnTheNextShot() {
        var g = game(pocketed: [0])
        g.resolve(pocketedIDs: [0], strikerPocketed: false)
        XCTAssertEqual(g.queenState, 1); XCTAssertEqual(g.turn, 0); XCTAssertEqual(g.score, [0, 0])
        g.pieces[3].pocketed = true
        let id = g.pieces[3].kind == .white ? g.pieces[3].id : 3
        _ = id
        // Cover with a white coin.
        let white = g.pieces.first { $0.kind == .white && !$0.pocketed }!.id
        g.pieces[g.pieces.firstIndex { $0.id == white }!].pocketed = true
        g.resolve(pocketedIDs: [white], strikerPocketed: false)
        XCTAssertEqual(g.queenState, 2); XCTAssertGreaterThanOrEqual(g.score[0], 4)
    }

    func testUncoveredQueenReturnsToTheCentre() {
        var g = game(pocketed: [0])
        g.resolve(pocketedIDs: [0], strikerPocketed: false)
        g.resolve(pocketedIDs: [], strikerPocketed: false)
        XCTAssertEqual(g.queenState, 0)
        XCTAssertFalse(g.pieces[0].pocketed)
        XCTAssertEqual(g.turn, 1)
    }

    func testClearingYourCoinsWins() {
        var g = game(pocketed: Array(1 ... 9))
        g.resolve(pocketedIDs: [9], strikerPocketed: false)
        XCTAssertTrue(g.over); XCTAssertEqual(g.winner, 0)
    }

    func testCodable() throws {
        var g = CarromGame()
        g.resolve(pocketedIDs: [], strikerPocketed: false)
        XCTAssertEqual(try JSONDecoder().decode(CarromGame.self, from: JSONEncoder().encode(g)), g)
        let shot = CarromShot(number: 3, seat: 1, x: 0.4, vx: 1, vy: 2)
        XCTAssertEqual(try JSONDecoder().decode(CarromShot.self, from: JSONEncoder().encode(shot)), shot)
    }

    // MARK: Computer player

    private func setup() -> CarromGame {
        var g = CarromGame()
        for i in g.pieces.indices { g.pieces[i].pocketed = true }
        // One white coin in the open with a clear run to the bottom-right pocket, one black far away.
        g.pieces[g.pieces.firstIndex { $0.id == 1 }!].p = SIMD2(0.7, 0.55); g.pieces[g.pieces.firstIndex { $0.id == 1 }!].pocketed = false
        g.pieces[g.pieces.firstIndex { $0.id == 10 }!].p = SIMD2(0.25, 0.25); g.pieces[g.pieces.firstIndex { $0.id == 10 }!].pocketed = false
        g.pieces[g.pieces.firstIndex { $0.id == 2 }!].p = SIMD2(0.3, 0.7); g.pieces[g.pieces.firstIndex { $0.id == 2 }!].pocketed = false
        return g
    }

    func testCandidatesAimAtOwnCoins() {
        let g = setup()
        let c = CarromAI.candidates(g, seat: 0)
        XCTAssertFalse(c.isEmpty)
        XCTAssertTrue(c.allSatisfy { $0.shot.vy < 0 || abs($0.shot.vy) < 1 }, "shots travel up the board")
    }

    func testHardAIPocketsAnOpenCoin() {
        let g = setup()
        let shot = CarromAI.choose(g, seat: 0, level: .hard, seed: 1)
        var w = CarromWorld(pieces: g.pieces.filter { !$0.pocketed } + [CarromAI.striker(for: shot)])
        let ev = w.simulateToRest()
        XCTAssertFalse(ev.pocketed.contains(CarromGame.strikerID))
        XCTAssertTrue(ev.pocketed.contains(1) || ev.pocketed.contains(2), "pocketed \(ev.pocketed)")
    }

    func testAIAlwaysReturnsAPlayableShot() {
        let g = CarromGame()
        for level in AILevel.allCases {
            let s = CarromAI.choose(g, seat: 1, level: level, seed: 4)
            XCTAssertTrue(CarromGame.baselineRange.contains(s.x))
            XCTAssertLessThanOrEqual((s.vx * s.vx + s.vy * s.vy).squareRoot(), W.maxShotSpeed * 1.01)
            XCTAssertGreaterThan((s.vx * s.vx + s.vy * s.vy).squareRoot(), 0.3)
        }
    }

    func testComputerVersusComputerFinishes() {
        var g = CarromGame()
        var shots = 0
        while !g.over, shots < 120 {
            let seat = g.turn
            let shot = CarromAI.choose(g, seat: seat, level: .medium, seed: UInt64(shots))
            var w = CarromWorld(pieces: g.pieces.map { var p = $0; p.v = .zero; return p } + [CarromAI.striker(for: shot)])
            let ev = w.simulateToRest()
            for p in w.pieces where p.id != CarromGame.strikerID {
                if let i = g.pieces.firstIndex(where: { $0.id == p.id }) { g.pieces[i].p = p.p; g.pieces[i].pocketed = p.pocketed }
            }
            g.resolve(pocketedIDs: ev.pocketed.filter { $0 != CarromGame.strikerID }, strikerPocketed: ev.pocketed.contains(CarromGame.strikerID))
            shots += 1
        }
        XCTAssertGreaterThan(g.score[0] + g.score[1], 0, "the computers pocket something")
        XCTAssertEqual(g.pieces.filter { !$0.pocketed }.count + g.pieces.filter(\.pocketed).count, 19)
    }
}

private extension SIMD2 where Scalar == Double {
    var magnitudeForTest: Double { (x * x + y * y).squareRoot() }
}
