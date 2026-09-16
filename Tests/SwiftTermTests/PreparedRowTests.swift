#if os(macOS)
import AppKit
import XCTest
@testable import SwiftTerm

final class PreparedRowTests: XCTestCase {
    func testUnchangedRowsReusePreparationAndMutationsInvalidate() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 200))
        view.feed(text: "hello 界")
        let line = view.terminal.buffer.lines[0]
        let first = view.preparedRow(row: 0, line: line, cols: 10)
        XCTAssertTrue(first === view.preparedRow(row: 0, line: line, cols: 10))
        line[0] = CharData.Null
        let changed = view.preparedRow(row: 0, line: line, cols: 10)
        XCTAssertFalse(first === changed)
        XCTAssertTrue(changed.info.segments.map { $0.attributedString.string }.joined().hasPrefix(" ello"))
        line.clear(with: CharData.defaultAttr)
        XCTAssertFalse(changed === view.preparedRow(row: 0, line: line, cols: 10))
    }

    func testContextAndIdentityInvalidationAndBound() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 200))
        let line = BufferLine(cols: 10)
        let first = view.preparedRow(row: 0, line: line, cols: 10)
        view.selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 2, row: 0))
        view.selection.active = true
        let selected = view.preparedRow(row: 0, line: line, cols: 10)
        XCTAssertFalse(first === selected)
        view.selectedTextBackgroundColor = .red
        XCTAssertFalse(selected === view.preparedRow(row: 0, line: line, cols: 10))
        let beforeTheme = view.preparedRow(row: 0, line: line, cols: 10)
        view.colorsChanged()
        XCTAssertFalse(beforeTheme === view.preparedRow(row: 0, line: line, cols: 10))
        let beforeRecycle = view.preparedRow(row: 0, line: line, cols: 10)
        XCTAssertFalse(beforeRecycle === view.preparedRow(row: 0, line: BufferLine(cols: 10), cols: 10))
        for row in 0..<1000 { _ = view.preparedRow(row: row, line: line, cols: 10) }
        XCTAssertLessThanOrEqual(view.preparedRows.count, 512)
    }

    func testLinksFontsImagesAndScrollingUseCurrentContext() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 200))
        view.feed(text: "界hello")
        let line = view.terminal.buffer.lines[0]
        let first = view.preparedRow(row: 0, line: line, cols: 10)
        view.linkHighlightMode = .hover
        view.linkHighlightRange = [.init(row: 0, range: 0..<7)]
        let linked = view.preparedRow(row: 0, line: line, cols: 10)
        XCTAssertFalse(first === linked)
        XCTAssertNotNil(linked.info.segments[0].attributedString.attribute(.underlineStyle, at: 0, effectiveRange: nil))
        let scrolled = view.preparedRow(row: 1, line: line, cols: 10)
        XCTAssertNil(scrolled.info.segments[0].attributedString.attribute(.underlineStyle, at: 0, effectiveRange: nil))
        view.font = NSFont.monospacedSystemFont(ofSize: 17, weight: .regular)
        let fontChanged = view.preparedRow(row: 0, line: line, cols: 10)
        XCTAssertFalse(linked === fontChanged)
        line.attach(image: MockTerminalImage())
        let imageChanged = view.preparedRow(row: 0, line: line, cols: 10)
        XCTAssertFalse(fontChanged === imageChanged)
        XCTAssertEqual(imageChanged.info.images?.count, 1)
        line.images = nil
        XCTAssertNil(view.preparedRow(row: 0, line: line, cols: 10).info.images)
        let fresh = view.buildAttributedString(row: 0, line: line, cols: 10)
        let cached = view.preparedRow(row: 0, line: line, cols: 10)
        XCTAssertEqual(cached.info.segments.map { $0.columnWidth }, fresh.segments.map { $0.columnWidth })
        XCTAssertEqual(cached.info.segments.map { $0.attributedString }, fresh.segments.map { $0.attributedString })
    }

    func testEveryCellMutationChangesRevision() {
        let line = BufferLine(cols: 12)
        let other = BufferLine(cols: 12)
        let operations: [() -> Void] = [
            { line[0] = .Null }, { line.fill(with: .Null) },
            { line.fill(with: .Null, atCol: 1, len: 2) },
            { line.insertCells(pos: 0, n: 1, rightMargin: 11, fillData: .Null) },
            { line.deleteCells(pos: 0, n: 1, rightMargin: 11, fillData: .Null) },
            { line.replaceCells(start: 0, end: 2, fillData: .Null) },
            { line.copyFrom(line: other) }, { line.copyFrom(other, srcCol: 0, dstCol: 0, len: 2) },
            { line.resize(cols: 13, fillData: .Null) }, { line.clear(with: CharData.defaultAttr) },
            { line.images = [] }, { line.renderMode = .doubleWidth }, { line.isWrapped = true }
        ]
        for operation in operations {
            let before = line.contentRevision
            operation()
            XCTAssertNotEqual(before, line.contentRevision)
        }
    }
}
#endif
