import Foundation
import Testing
@testable import Zashiki

struct CachedValueTests {
    @Test func cachesAndInvalidates() {
        var reads = 0
        let cache = CachedValue(duration: .seconds(60)) {
            reads += 1
            return "日本語 \(reads)"
        }
        #expect(cache.get() == cache.get())
        #expect(reads == 1)
        cache.invalidate()
        _ = cache.get()
        #expect(reads == 2)
    }

    @Test func fetchCanReenterAndInvalidate() {
        var reads = 0
        var cache: CachedValue<Int>!
        cache = CachedValue(duration: .seconds(60)) {
            reads += 1
            if reads == 1 {
                cache.invalidate()
                return cache.get()
            }
            return reads
        }
        #expect(cache.get() == 2)
        #expect(cache.get() == 2)
        #expect(reads == 2)
        // Break the test's intentional closure cycle.
        cache = nil
    }

    @Test func invalidationDuringFetchDoesNotPublishOldResult() async {
        let entered = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        let reads = LockedCounter()
        let cache = CachedValue(duration: .seconds(60)) {
            let read = reads.next()
            if read == 1 {
                entered.signal()
                resume.wait()
            }
            return read
        }
        let first = Task.detached { cache.get() }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                entered.wait()
                continuation.resume()
            }
        }
        cache.invalidate()
        #expect(cache.get() == 2)
        resume.signal()
        #expect(await first.value == 1)
        #expect(cache.get() == 2)
    }

    @Test func cancelledExpiryCannotClearANewerValue() async {
        let sleeper = ControlledSleep()
        let reads = LockedCounter()
        let cache = CachedValue(duration: .zero, sleep: { _ in await sleeper.sleep() }, fetch: { reads.next() })
        #expect(cache.get() == 1)
        await sleeper.waitForCount(1)
        cache.invalidate()
        #expect(cache.get() == 2)
        await sleeper.waitForCount(2)
        // Simulate an old sleep that completed just before cancellation.
        await sleeper.resume(0)
        for _ in 0..<100 { await Task.yield() }
        #expect(cache.get() == 2)
        await sleeper.resume(1)
        for _ in 0..<10_000 {
            if cache.get() == 3 { break }
            await Task.yield()
        }
        #expect(cache.get() == 3)
        await sleeper.waitForCount(3)
        cache.invalidate()
        await sleeper.resume(2)
    }

    @Test func concurrentReadsInvalidationsAndExpiry() async throws {
        let reads = LockedCounter()
        let cache = CachedValue(duration: .microseconds(50)) { "日本語 \(reads.next())" }
        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<8 {
                group.addTask {
                    for index in 0..<4_000 {
                        #expect(cache.get().hasPrefix("日本語 "))
                        if (index + worker) % 7 == 0 { cache.invalidate() }
                    }
                }
            }
        }
        try await Task.sleep(for: .milliseconds(5))
        #expect(cache.get().hasPrefix("日本語 "))
    }

    @Test func expiryDoesNotRetainCache() async {
        weak var weakCache: CachedValue<String>?
        do {
            let cache = CachedValue(duration: .seconds(60)) { "text" }
            weakCache = cache
            _ = cache.get()
        }
        #expect(weakCache == nil)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private actor ControlledSleep {
    private var continuations: [CheckedContinuation<Void, Never>?] = []
    func sleep() async {
        await withCheckedContinuation { continuations.append($0) }
    }
    func waitForCount(_ count: Int) async {
        while continuations.count < count { await Task.yield() }
    }
    func resume(_ index: Int) {
        continuations[index]?.resume()
        continuations[index] = nil
    }
}
