import XCTest
@testable import Khel

final class SnakeTests: XCTestCase {
    typealias E = SnakeEngine

    func testMovesForward() {
        var e = E(seed: 1)
        let head = e.body[0]
        e.food = E.Point(x: 0, y: 0)
        XCTAssertEqual(e.tick(), .none)
        XCTAssertEqual(e.body[0], E.Point(x: head.x + 1, y: head.y))
        XCTAssertEqual(e.body.count, 3)
    }

    func testEatingGrowsAndScores() {
        var e = E(seed: 1)
        e.food = E.Point(x: e.body[0].x + 1, y: e.body[0].y)
        XCTAssertEqual(e.tick(), .ate)
        XCTAssertEqual(e.body.count, 4); XCTAssertEqual(e.score, 10)
        XCTAssertFalse(e.body.contains(e.food))
    }

    func testWallKillsInClassicButWrapsInWrap() {
        var c = E(mode: .classic, seed: 1)
        c.food = E.Point(x: 0, y: 0)
        var n = 0
        while c.alive, n < 100 { c.tick(); n += 1 }
        XCTAssertFalse(c.alive)
        var w = E(mode: .wrap, seed: 1)
        w.food = E.Point(x: 0, y: 0)
        for _ in 0 ..< 40 { w.tick() }
        XCTAssertTrue(w.alive)
        XCTAssertTrue((0 ..< w.cols).contains(w.body[0].x))
    }

    func testCannotReverseAndBuffersTwoTurns() {
        var e = E(seed: 1)
        e.turn(.left)
        XCTAssertTrue(e.queued.isEmpty, "reversing into the body is ignored")
        e.turn(.up); e.turn(.left); e.turn(.down)
        XCTAssertEqual(e.queued, [.up, .left])
        e.food = E.Point(x: 0, y: 0)
        e.tick(); XCTAssertEqual(e.dir, .up)
        e.tick(); XCTAssertEqual(e.dir, .left)
    }

    func testSelfCollisionKills() {
        var e = E(seed: 1)
        e.body = [E.Point(x: 5, y: 5), E.Point(x: 5, y: 6), E.Point(x: 6, y: 6), E.Point(x: 6, y: 5), E.Point(x: 6, y: 4)]
        e.dir = .up
        e.queued = [.right]
        e.food = E.Point(x: 0, y: 0)
        XCTAssertEqual(e.tick(), .died)
        XCTAssertFalse(e.alive)
    }

    func testFollowingTheTailIsSafe() {
        var e = E(seed: 1)
        e.body = [E.Point(x: 5, y: 5), E.Point(x: 5, y: 6), E.Point(x: 4, y: 6), E.Point(x: 4, y: 5)]
        e.dir = .left
        e.food = E.Point(x: 0, y: 0)
        XCTAssertEqual(e.tick(), .none, "the tail cell is freed in the same tick")
        XCTAssertTrue(e.alive)
    }

    func testSpeedsUpAndCodable() throws {
        var e = E(mode: .speed, seed: 1)
        let slow = e.interval
        e.score = 100
        XCTAssertLessThan(e.interval, slow)
        XCTAssertGreaterThanOrEqual(e.interval, 0.055)
        XCTAssertEqual(try JSONDecoder().decode(E.self, from: JSONEncoder().encode(e)).body, e.body)
    }

    func testFoodNeverOnSnake() {
        var e = E(seed: 5)
        for _ in 0 ..< 200 { e.placeFood(); XCTAssertFalse(e.body.contains(e.food)) }
    }
}
