#if !os(iOS) && !os(Windows)
import XCTest
@testable import SwiftTerm

final class ProcessDeliveryTests: XCTestCase {
    func testSlicesRotateAcrossProcessesAndYieldAtSharedDeadline() {
        var turns: [() -> Void] = []
        var now: UInt64 = 0
        var events: [Int] = []
        let scheduler = ProcessDeliveryScheduler(sliceBytes: 2, budgetNanoseconds: 3,
            clock: { now }, schedule: { turns.append($0) })
        scheduler.enqueue(stream: 1, bytes: [1, 2, 3, 4, 5], deliver: { bytes in
            XCTAssertLessThanOrEqual(bytes.count, 2)
            events.append(1); now += 2
        }, consumed: {})
        scheduler.enqueue(stream: 2, bytes: [6, 7, 8, 9], deliver: { _ in events.append(2); now += 2 }, consumed: {})
        XCTAssertEqual(turns.count, 1)
        turns.removeFirst()()
        XCTAssertEqual(events, [1, 2])
        XCTAssertEqual(turns.count, 1)
        turns.removeFirst()()
        XCTAssertEqual(events, [1, 2, 1, 2])
        turns.removeFirst()()
        XCTAssertEqual(events, [1, 2, 1, 2, 1])
        XCTAssertTrue(turns.isEmpty)
    }

    func testFragmentedBytesStayOrderedAndConsumedOnlyAfterLastSlice() {
        var turns: [() -> Void] = []
        var output: [UInt8] = []
        var completed: [Int] = []
        let (fragmented, delegate) = TerminalTestHarness.makeTerminal()
        let (whole, wholeDelegate) = TerminalTestHarness.makeTerminal()
        let scheduler = ProcessDeliveryScheduler(sliceBytes: 1, budgetNanoseconds: 3,
            clock: { 0 }, schedule: { turns.append($0) })
        let expected = Array("\u{1b}[31m界👩🏽‍💻\u{1b}[0m\r\n".utf8)
        for (index, byte) in expected.enumerated() {
            scheduler.enqueue(stream: 1, bytes: [byte], deliver: { output.append(contentsOf: $0); fragmented.feed(buffer: $0) }, consumed: {
                XCTAssertEqual(output.count, index + 1)
                completed.append(index)
            })
        }
        while !turns.isEmpty { turns.removeFirst()() }
        whole.feed(byteArray: expected)
        XCTAssertEqual(TerminalTestHarness.visibleLinesText(buffer: fragmented.buffer, terminal: fragmented),
                       TerminalTestHarness.visibleLinesText(buffer: whole.buffer, terminal: whole))
        XCTAssertEqual(fragmented.buffer.lines[0][0].attribute, whole.buffer.lines[0][0].attribute)
        withExtendedLifetime((delegate, wholeDelegate)) {}
        XCTAssertEqual(output, expected)
        XCTAssertEqual(completed, Array(expected.indices))
    }

    func testReadBackpressureBoundsPendingBytesUntilConsumption() {
        var turns: [() -> Void] = []
        var pending = 0
        var reads = 0
        let readSize = 128 * 1024
        let scheduler = ProcessDeliveryScheduler(sliceBytes: 16 * 1024, budgetNanoseconds: 1,
            clock: { 0 }, schedule: { turns.append($0) })
        let gate = ProcessReadGate { reads += 1 }
        // Model DispatchIO's maximum one operation, split into partial callbacks.
        for _ in 0..<8 {
            gate.received()
            pending += readSize / 8
            scheduler.enqueue(stream: 1, bytes: Array(repeating: 1, count: readSize / 8),
                deliver: { pending -= $0.count }, consumed: { gate.consumed() })
        }
        gate.finished()
        XCTAssertEqual(pending, readSize)
        XCTAssertEqual(reads, 0)
        while !turns.isEmpty { turns.removeFirst()() }
        XCTAssertEqual(pending, 0)
        XCTAssertEqual(reads, 1)
    }

    func testReadGateWaitsForDoneAndAllDeliveriesBeforeResuming() {
        var resumed = 0
        let gate = ProcessReadGate { resumed += 1 }
        gate.received()
        gate.received()
        gate.consumed()
        XCTAssertEqual(resumed, 0)
        gate.finished()
        XCTAssertEqual(resumed, 0)
        gate.consumed()
        XCTAssertEqual(resumed, 1)
    }
}
#endif
#if os(macOS)
private final class DeliveryProcessDelegate: LocalProcessDelegate {
    var output: [UInt8] = []
    var maxSlice = 0
    let finished: XCTestExpectation
    init(_ finished: XCTestExpectation) { self.finished = finished }
    func dataReceived(slice: ArraySlice<UInt8>) {
        XCTAssertTrue(Thread.isMainThread)
        maxSlice = max(maxSlice, slice.count)
        output.append(contentsOf: slice)
    }
    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        XCTAssertTrue(Thread.isMainThread)
        finished.fulfill()
    }
    func getWindowSize() -> winsize { winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0) }
}

extension ProcessDeliveryTests {
    func testActualPTYFlushesMoreThanOneReadBeforeExitNotification() {
        let finished = expectation(description: "PTY EOF and all output delivered")
        let delegate = DeliveryProcessDelegate(finished)
        let process = LocalProcess(delegate: delegate)
        let fragment = "\u{1b}[31m界x\u{1b}[0m"
        process.startProcess(executable: "/bin/sh", args: ["-c", "i=0; while [ $i -lt 16000 ]; do printf '\(fragment)'; i=$((i+1)); done"])
        wait(for: [finished], timeout: 20)
        XCTAssertEqual(delegate.output, Array(String(repeating: fragment, count: 16000).utf8))
        XCTAssertLessThanOrEqual(delegate.maxSlice, 16 * 1024)
        XCTAssertFalse(process.running)
        process.io?.close()
    }
}
#endif
