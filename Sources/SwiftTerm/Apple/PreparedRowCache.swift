#if os(macOS) || os(iOS) || os(visionOS)
import Foundation
import CoreText

/// Prepared text, not pixels: image placement, glyph positioning and decorations
/// are still drawn against the current CGContext and cell dimensions each frame.
final class PreparedRow {
    let info: ViewLineInfo
    let segments: [(segment: ViewLineSegment, ctLine: CTLine, runs: [CTRun])]
    init(info: ViewLineInfo) {
        self.info = info
        segments = info.segments.compactMap { segment in
            guard segment.attributedString.length > 0 else { return nil }
            let ctLine = CTLineCreateWithAttributedString(segment.attributedString)
            guard let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] else { return nil }
            return (segment, ctLine, runs)
        }
    }
}

struct PreparedRowContext: Equatable {
    let columns: Int
    let selection: Range<Int>?
    let selectionColor: TTColor
    let highlight: Range<Int>?
    let highlightMode: LinkHighlightMode
    let commandActive: Bool
    let customBlocks: Bool
    let cellSize: CGSize
    let appearance: String
}

final class PreparedRowCache {
    private struct Entry {
        weak var line: BufferLine?
        let revision: UInt64
        let context: PreparedRowContext
        let prepared: PreparedRow
        var used: UInt64
    }
    private var entries: [Int: Entry] = [:]
    private var generation: UInt64 = 0
    var count: Int { entries.count }
    func removeAll() { entries.removeAll(keepingCapacity: true) }

    func row(_ row: Int, line: BufferLine, context: PreparedRowContext, limit: Int,
             build: () -> ViewLineInfo) -> PreparedRow {
        generation &+= 1
        if var entry = entries[row], entry.line === line,
           entry.revision == line.contentRevision, entry.context == context {
            entry.used = generation
            entries[row] = entry
            return entry.prepared
        }
        let prepared = PreparedRow(info: build())
        entries[row] = Entry(line: line, revision: line.contentRevision, context: context,
                             prepared: prepared, used: generation)
        while entries.count > limit, let oldest = entries.min(by: { $0.value.used < $1.value.used }) {
            entries.removeValue(forKey: oldest.key)
        }
        return prepared
    }
}

extension TerminalView {
    func preparedRow(row: Int, line: BufferLine, cols: Int) -> PreparedRow {
#if os(macOS)
        let appearance = effectiveAppearance.name.rawValue
#else
        let appearance = String(traitCollection.userInterfaceStyle.rawValue)
#endif
        let context = PreparedRowContext(columns: cols,
            selection: selectedColumnsRange(row: row, cols: cols), selectionColor: selectedTextBackgroundColor,
            highlight: linkHighlightRange?.first(where: { $0.row == row })?.range,
            highlightMode: linkHighlightMode, commandActive: commandActive,
            customBlocks: customBlockGlyphs, cellSize: cellDimension, appearance: appearance)
        return preparedRows.row(row, line: line, context: context, limit: min(512, max(32, terminal.rows * 2))) {
            buildAttributedString(row: row, line: line, cols: cols)
        }
    }
}
#endif
