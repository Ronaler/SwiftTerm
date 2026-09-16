#if !os(iOS) && !os(Windows)
import Foundation
import Dispatch

/// Fair delivery for all main-queue PTYs. Producers may enqueue from their read
/// queues; only the injected scheduler invokes delegates. No lock is held while
/// calling client code. LocalProcess gates its next read on consumption, bounding
/// each process to one readSize operation (including partial callbacks).
final class ProcessDeliveryScheduler {
    static let shared = ProcessDeliveryScheduler()
    private struct Chunk {
        var bytes: ArraySlice<UInt8>
        let deliver: (ArraySlice<UInt8>) -> Void
        let consumed: () -> Void
    }
    private let sliceBytes: Int
    private let budgetNanoseconds: UInt64
    private let clock: () -> UInt64
    private let schedule: (@escaping () -> Void) -> Void
    private let lock = NSLock()
    private var streams: [AnyHashable: [Chunk]] = [:]
    private var ready: [AnyHashable] = []
    private var scheduled = false

    init(sliceBytes: Int = 16 * 1024, budgetNanoseconds: UInt64 = 3_000_000,
         clock: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
         schedule: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) {
        precondition(sliceBytes > 0 && budgetNanoseconds > 0)
        self.sliceBytes = sliceBytes
        self.budgetNanoseconds = budgetNanoseconds
        self.clock = clock
        self.schedule = schedule
    }

    func enqueue(stream: AnyHashable, bytes: [UInt8], deliver: @escaping (ArraySlice<UInt8>) -> Void,
                 consumed: @escaping () -> Void) {
        lock.lock()
        if streams[stream] == nil { ready.append(stream) }
        streams[stream, default: []].append(Chunk(bytes: bytes[...], deliver: deliver, consumed: consumed))
        let start = !scheduled
        scheduled = true
        lock.unlock()
        if start { schedule { self.drain() } }
    }

    private func drain() {
        let start = clock()
        repeat {
            lock.lock()
            guard !ready.isEmpty else {
                scheduled = false
                lock.unlock()
                return
            }
            let stream = ready.removeFirst()
            var chunks = streams.removeValue(forKey: stream)!
            var chunk = chunks.removeFirst()
            let bytes = chunk.bytes.prefix(sliceBytes)
            chunk.bytes = chunk.bytes.dropFirst(bytes.count)
            let finished = chunk.bytes.isEmpty
            if !finished { chunks.insert(chunk, at: 0) }
            if !chunks.isEmpty {
                streams[stream] = chunks
                ready.append(stream)
            }
            lock.unlock()
            chunk.deliver(bytes)
            if finished { chunk.consumed() }
        } while clock() &- start < budgetNanoseconds

        lock.lock()
        let again = !ready.isEmpty
        if !again { scheduled = false }
        lock.unlock()
        if again { schedule { self.drain() } }
    }
}

/// Confined to a LocalProcess read queue. DispatchIO can produce multiple partial
/// callbacks for one read: only `done` plus consumption of every callback permits
/// the next read. This prevents multiplying read chains or unbounded queued input.
final class ProcessReadGate {
    private var outstanding = 0
    private var done = false
    private var resumed = false
    private let resume: () -> Void
    init(resume: @escaping () -> Void) { self.resume = resume }
    func received() { outstanding += 1 }
    func consumed() { outstanding -= 1; check() }
    func finished() { done = true; check() }
    private func check() {
        if done && outstanding == 0 && !resumed {
            resumed = true
            resume()
        }
    }
}
#endif
