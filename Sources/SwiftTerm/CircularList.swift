// Circular storage shared by terminal history and reflow working lists.
import Foundation

enum ArgumentError: Error {
    case invalidArgument(String)
}

class CircularList<T> {
    private var array: [T?] = []
    private var startIndex = 0
    private var _count = 0

    var count: Int {
        get { _count }
        set {
            precondition(newValue >= 0 && newValue <= maxLength)
            ensureStorage(newValue)
            if newValue < _count {
                for i in newValue..<_count { array[cyclic(i)] = nil }
            }
            _count = newValue
        }
    }

    // Logical limit is independent of allocation. In particular, changing rows
    // must not allocate or scan the configured scrollback capacity.
    var maxLength: Int {
        didSet {
            precondition(maxLength >= 0)
            if maxLength < oldValue {
                let end = min(oldValue, array.count)
                if maxLength < end {
                    for i in maxLength..<end { array[cyclic(i)] = nil }
                }
                _count = min(_count, maxLength)
            }
        }
    }

    var makeEmpty: ((_ idx: Int) -> T)?
    init(maxLength: Int) {
        precondition(maxLength >= 0)
        self.maxLength = maxLength
    }

    @inline(__always)
    private func cyclic(_ index: Int) -> Int {
        let slot = startIndex + index
        return slot < array.count ? slot : slot % array.count
    }

    @inline(__always)
    private func prepareSlot(_ index: Int) -> Int {
        precondition(index >= 0 && maxLength > 0)
        // Ordinary parser access is already inside the logical ring. Preserve
        // cyclic lookahead without paying for a second division on every cell.
        let logical = index < maxLength ? index : index % maxLength
        ensureStorage(logical + 1)
        return cyclic(logical)
    }

    @inline(__always)
    private func ensureStorage(_ required: Int) {
        guard required > array.count else { return }
        // Keep slack even at the logical limit: a +/-1 row change at full
        // history should not repeatedly copy all materialized lines either.
        let capacity = max(required, max(16, array.count * 2))
        var replacement = [T?](repeating: nil, count: capacity)
        for i in 0..<array.count { replacement[i] = array[cyclic(i)] }
        array = replacement
        startIndex = 0
    }

    var isEmpty: Bool { count == 0 }
    var isFull: Bool { count == maxLength }
    func getArray() -> [T?] { array }
    func getStartIndex() -> Int { startIndex }
    func debugGetCyclicIndex(_ index: Int) -> Int {
        ensureStorage(index + 1)
        return cyclic(index)
    }

    subscript(index: Int) -> T {
        _read {
            let slot = prepareSlot(index)
            if array[slot] == nil { array[slot] = makeEmpty!(slot) }
            yield array[slot]!
        }
        set {
            let slot = prepareSlot(index)
            array[slot] = newValue
        }
    }

    func push(_ value: T) { append(value) }

    // Used by specialized recycling without generating an extra pushed event.
    fileprivate func append(_ value: T) {
        precondition(maxLength > 0)
        ensureStorage(min(count + 1, maxLength))
        if isFull {
            let tail = cyclic(count)
            let first = startIndex
            array[first] = nil
            array[tail] = value
            startIndex = (first + 1) % array.count
        } else {
            array[cyclic(count)] = value
            _count += 1
        }
    }

    func recycle() {
        precondition(isFull)
        append(makeEmpty!(-1))
    }

    @discardableResult
    func pop() -> T {
        precondition(count > 0)
        let value = self[count - 1]
        count -= 1
        return value
    }

    func trimStart(count requested: Int) {
        let removed = min(max(0, requested), count)
        guard removed > 0 else { return }
        for i in 0..<removed { array[cyclic(i)] = nil }
        startIndex = cyclic(removed)
        _count -= removed
    }

    func splice(start: Int, deleteCount: Int, items: [T], change: (Int) -> Void) {
        precondition(start >= 0 && start <= count && deleteCount >= 0 && start + deleteCount <= count)
        // Splicing already moves the suffix. Snapshot it to avoid overwriting
        // wrapped sources when insertion also trims the head at the limit.
        let changedStart = count - deleteCount + items.count > maxLength ? 0 : start
        let suffix = (start + deleteCount..<count).map { array[cyclic($0)] }
        count = start
        for value in items { append(value) }
        for value in suffix {
            if let value { append(value) } else {
                if isFull { trimStart(count: 1) }
                count += 1
            }
        }
        for i in min(changedStart, count)..<count { change(i) }
    }

    func shiftElements(start: Int, count length: Int, offset: Int) -> Bool {
        guard length >= 0, start >= 0, start < count,
              start + length <= count, start + offset > 0 else { return false }
        let values = (start..<start + length).map { array[cyclic($0)] }
        let expanded = max(count, start + length + offset)
        let trimmed = max(0, expanded - maxLength)
        trimStart(count: trimmed)
        count = min(maxLength, expanded)
        for (i, value) in values.enumerated() {
            let destination = start + i + offset - trimmed
            if destination >= 0 && destination < count { array[cyclic(destination)] = value }
        }
        return true
    }
}

internal final class CircularBufferLineList: CircularList<BufferLine> {
    var onLineRecycled: ((_ hadImages: Bool) -> Void)?
    var onLinePushed: ((_ hasImages: Bool) -> Void)?

    override func push(_ value: BufferLine) {
        super.push(value)
        onLinePushed?(value.images != nil)
    }

    func recycle(clearAttribute: Attribute) {
        precondition(isFull)
        let line = self[0]
        let hadImages = line.images != nil
        append(line)
        line.clear(with: clearAttribute)
        onLineRecycled?(hadImages)
    }
}
