import XCTest
@testable import SwiftTerm

final class CircularStorageTests: XCTestCase {
    func testSparseLargeLimitReusesAllocation() {
        let ring = CircularBufferLineList(maxLength: 500_024)
        for _ in 0..<24 { ring.push(BufferLine(cols: 4)) }
        XCTAssertLessThan(ring.getArray().count, 128)
        let capacity = ring.getArray().count
        let first = ring[0]
        for _ in 0..<100 {
            ring.maxLength += 1
            ring.maxLength -= 1
        }
        XCTAssertEqual(ring.getArray().count, capacity)
        XCTAssertTrue(ring[0] === first)
        XCTAssertEqual(ring.getArray().compactMap { $0 }.count, 24)
    }

    func testWrappedGrowTrimShrinkGrow() {
        let ring = CircularBufferLineList(maxLength: 5)
        let lines = (0..<14).map { _ in BufferLine(cols: 1) }
        for line in lines.prefix(9) { ring.push(line) }
        for i in 0..<5 { XCTAssertTrue(ring[i] === lines[i + 4]) }
        ring.maxLength = 9
        for line in lines.suffix(5) { ring.push(line) }
        for i in 0..<9 { XCTAssertTrue(ring[i] === lines[i + 5]) }
        ring.trimStart(count: 6)
        ring.maxLength = 3
        ring.maxLength = 100
        for i in 0..<3 { XCTAssertTrue(ring[i] === lines[i + 11]) }
        XCTAssertEqual(ring.getArray().compactMap { $0 }.count, 3)
    }

    func testCyclicLookaheadAtLogicalLimit() {
        let ring = CircularList<Int>(maxLength: 2)
        ring.push(10)
        ring.push(20)
        XCTAssertEqual(ring[2], ring[0])
        ring.push(30)
        XCTAssertEqual(ring[2], ring[0])
    }

    func testGenericOrderAndOversizedTrim() {
        let ring = CircularList<Int>(maxLength: 3)
        for i in 0..<8 { ring.push(i) }
        XCTAssertEqual((0..<ring.count).map { ring[$0] }, [5, 6, 7])
        ring.trimStart(count: 20)
        XCTAssertEqual(ring.count, 0)
    }

    func testUnusedSlotsSurviveGrowthAndClearedSlotsStayEmpty() {
        let ring = CircularBufferLineList(maxLength: 100)
        ring.makeEmpty = { _ in BufferLine(cols: 2) }
        ring.count = 3
        let line = ring[12]
        ring.maxLength = 101
        XCTAssertTrue(ring[12] === line)
        ring.maxLength = 5
        ring.maxLength = 101
        XCTAssertFalse(ring[12] === line)
    }
}
