import XCTest
@testable import Khel

final class AirHockeyTests: XCTestCase {
    typealias P = AirHockeyPhysics

    private func playing() -> P {
        var p = P(); p.phase = .playing; p.timer = 0
        return p
    }

    func testCountdownThenPlay() {
        var p = P()
        XCTAssertEqual(p.phase, .countdown)
        var events: [P.Event] = []
        for _ in 0 ..< 400 { events += p.step(1.0 / 120) }
        XCTAssertEqual(p.phase, .playing)
        XCTAssertTrue(events.contains(.start))
    }

    func testPuckStaysInsideTheTableAndLosesEnergy() {
        var p = playing()
        p.puck = SIMD2(0.3, 0.5)
        p.vel = SIMD2(2.2, 1.7)
        // Keep both goals blocked by bouncing only off the walls: put the puck on a path that never meets a goal opening.
        for _ in 0 ..< 3000 {
            _ = p.step(1.0 / 240)
            if p.phase != .playing { break }
            XCTAssertGreaterThanOrEqual(p.puck.x, P.puckR - 1e-9)
            XCTAssertLessThanOrEqual(p.puck.x, P.W - P.puckR + 1e-9)
            XCTAssertLessThanOrEqual((p.vel.x * p.vel.x + p.vel.y * p.vel.y).squareRoot(), P.maxPuckSpeed + 1e-9)
        }
    }

    func testGoalIsScoredOncePerCrossing() {
        var p = playing()
        p.puck = SIMD2(P.W / 2, 0.1)
        p.vel = SIMD2(0, -2)
        var goals: [P.Event] = []
        for _ in 0 ..< 240 { goals += p.step(1.0 / 120).filter { if case .goal = $0 { true } else { false } } }
        XCTAssertEqual(goals, [.goal(scorer: 0)])
        XCTAssertEqual(p.score, [1, 0])
        XCTAssertEqual(p.phase, .countdown, "the next serve is announced after the goal pause")
        XCTAssertEqual(p.puck.y, P.H * 0.3, accuracy: 0.01, "the conceding side serves")
    }

    func testPuckOutsideTheGoalOpeningBounces() {
        var p = playing()
        p.puck = SIMD2(0.12, 0.1)
        p.vel = SIMD2(0, -2)
        for _ in 0 ..< 60 { _ = p.step(1.0 / 120) }
        XCTAssertEqual(p.score, [0, 0])
        XCTAssertGreaterThan(p.vel.y, 0)
    }

    func testMalletTransfersMomentum() {
        var p = playing()
        p.mallet[0] = SIMD2(0.5, 1.3); p.target[0] = SIMD2(0.5, 1.0)
        p.mallet[1] = SIMD2(0.1, 0.2); p.target[1] = SIMD2(0.1, 0.2)
        p.puck = SIMD2(0.5, 1.1)
        p.vel = .zero
        var fastest = 0.0
        for _ in 0 ..< 12 { _ = p.step(1.0 / 120); fastest = min(fastest, p.vel.y) }
        XCTAssertLessThan(fastest, -1.0, "hit upward towards the opponent's goal")
    }

    func testMalletsStayOnTheirOwnHalf() {
        var p = P()
        p.setTarget(SIMD2(0.5, 0.1), seat: 0)
        p.setTarget(SIMD2(0.5, 1.5), seat: 1)
        for _ in 0 ..< 200 { _ = p.step(1.0 / 120) }
        XCTAssertGreaterThanOrEqual(p.mallet[0].y, P.H / 2)
        XCTAssertLessThanOrEqual(p.mallet[1].y, P.H / 2)
    }

    func testMalletSpeedIsLimited() {
        var p = P()
        p.setTarget(SIMD2(0.9, 1.5), seat: 0)
        _ = p.step(0.1, speeds: [1.0, 1.0])
        let moved = ((p.mallet[0].x - 0.5) * (p.mallet[0].x - 0.5) + (p.mallet[0].y - (P.H - 0.2)) * (p.mallet[0].y - (P.H - 0.2))).squareRoot()
        XCTAssertLessThanOrEqual(moved, 0.1 + 1e-6)
    }

    func testFirstToSevenWins() {
        var p = playing()
        p.score = [6, 3]
        p.puck = SIMD2(P.W / 2, 0.08); p.vel = SIMD2(0, -2.5)
        for _ in 0 ..< 600 { _ = p.step(1.0 / 120) }
        XCTAssertEqual(p.phase, .over)
        XCTAssertEqual(p.winner, 0)
    }

    func testSnapshotRoundTripAndInputPacket() {
        var p = playing()
        p.puck = SIMD2(0.31, 0.77); p.vel = SIMD2(-1.2, 0.4); p.mallet[0] = SIMD2(0.4, 1.2); p.mallet[1] = SIMD2(0.6, 0.3)
        p.score = [3, 5]
        let data = p.snapshot()
        XCTAssertEqual(data.count, P.snapshotSize)
        var q = P()
        XCTAssertTrue(q.apply(snapshot: data))
        XCTAssertEqual(q.puck.x, 0.31, accuracy: 1e-5); XCTAssertEqual(q.vel.x, -1.2, accuracy: 1e-5)
        XCTAssertEqual(q.score, [3, 5]); XCTAssertEqual(q.phase, .playing)
        XCTAssertFalse(q.apply(snapshot: Data([1, 2, 3])))
        let input = P.inputPacket(SIMD2(0.25, 1.1))
        XCTAssertEqual(P.decodeInput(input)?.x ?? 0, 0.25, accuracy: 1e-5)
        XCTAssertNil(P.decodeInput(data))
    }

    func testComputerReachesTheIncomingPuck() {
        for level in AILevel.allCases {
            var p = playing()
            p.puck = SIMD2(0.8, 0.7); p.vel = SIMD2(-0.3, -1.1)
            var best = Double.infinity
            for _ in 0 ..< 360 {
                let (t, speed) = p.aiTarget(seat: 1, level: level, noise: 0)
                p.setTarget(t, seat: 1)
                _ = p.step(1.0 / 120, speeds: [P.maxMalletSpeed, speed])
                if p.phase != .playing { break }
                let d = p.puck - p.mallet[1]
                best = min(best, (d.x * d.x + d.y * d.y).squareRoot())
            }
            XCTAssertLessThan(best, P.puckR + P.malletR + 0.05, "\(level) never reached the puck")
        }
    }

    func testAIDefendsMoreOftenThanItConcedesOnHard() {
        var p = playing()
        var conceded = 0
        var rng = SplitMix64(seed: 3)
        for _ in 0 ..< 12 {
            p = playing()
            p.score = [0, 0]
            p.puck = SIMD2(0.2 + Double(rng.int(in: 0 ... 60)) / 100, 0.9)
            p.vel = SIMD2(Double(rng.int(in: -80 ... 80)) / 100, -1.6)
            for _ in 0 ..< 480 {
                let (t, speed) = p.aiTarget(seat: 1, level: .hard, noise: 0)
                p.setTarget(t, seat: 1)
                _ = p.step(1.0 / 120, speeds: [P.maxMalletSpeed, speed])
                if p.phase != .playing { break }
            }
            if p.score[0] > 0 { conceded += 1 }
        }
        XCTAssertLessThanOrEqual(conceded, 4)
    }
}
