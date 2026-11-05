import Foundation
import Testing
import MachOKit
@testable import MachOReading
import MachOFixtureSupport

/// A file's mapping is created on its first read and shared by every read
/// after it. Several readers can make that first read at once: `diff` and
/// `evolution` prepare their inputs concurrently, and each input's dependency
/// lookup reads the host's dyld cache, which `FullDyldCache.cachedHost` opens
/// once per process, through the cache instances MachOKit assembles for it —
/// all of them sharing one mapping per file (`SharedFileMappingTests`). Every
/// accessor must hand all of them one object. Created unlocked, each racing
/// reader opened the file again and stored its own over the others'.
@Suite
struct ConcurrentFileMappingTests {
    /// How many readers make the first read of one instance together.
    private static let readerCount = 32

    /// How many fresh instances each test races on: one round can miss the
    /// overlap, which a wrong accessor shows in nearly every round.
    private static let roundCount = 20

    private static var isHostDyldCacheAvailable: Bool {
        FileManager.default.fileExists(atPath: DyldSharedCachePath.current.rawValue)
    }

    @Test func concurrentFirstReadsOfAFileShareOneMapping() throws {
        for _ in 0 ..< Self.roundCount {
            let machOFile = try Self.freshFixtureFile()
            let distinctCount = try Self.distinctObjectCount { try machOFile.fileIO }
            #expect(distinctCount == 1, "\(distinctCount) mappings of one file")
        }
    }

    @Test(.enabled(if: isHostDyldCacheAvailable))
    func concurrentFirstReadsOfADyldCacheShareOneMapping() throws {
        for _ in 0 ..< Self.roundCount {
            let dyldCache = try DyldCache(path: .current)
            let distinctCount = try Self.distinctObjectCount { try dyldCache.fileIO }
            #expect(distinctCount == 1, "\(distinctCount) mappings of one cache file")
        }
    }

    /// A new instance each time, opened afresh: the accessor under test must
    /// not have run on it, nor on anything sharing its opening, yet.
    private static func freshFixtureFile() throws -> MachOFile {
        switch try loadFromFile(named: .SymbolTestsCore) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            return try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
    }

    /// How many distinct objects `read` hands `readerCount` readers released
    /// together. Throws what the first failing read threw.
    ///
    /// The readers are threads of the test's own, not the global dispatch
    /// queue: this body blocks a cooperative thread until they finish (the
    /// same arrangement as `SharedCacheResolveTests`). Each one is parked on
    /// the start signal before any is let go, so the first reads overlap as
    /// closely as threads allow.
    private static func distinctObjectCount(returnedBy read: @escaping () throws -> AnyObject) throws -> Int {
        let reader = UncheckedReader(read: read)
        let handedObjects = HandedObjects()
        let readersReady = DispatchGroup()
        let readersFinished = DispatchGroup()
        let startSignal = DispatchSemaphore(value: 0)
        for _ in 0 ..< readerCount {
            readersReady.enter()
            readersFinished.enter()
            Thread {
                readersReady.leave()
                startSignal.wait()
                handedObjects.append(Result { try reader.read() })
                readersFinished.leave()
            }.start()
        }
        readersReady.wait()
        for _ in 0 ..< readerCount {
            startSignal.signal()
        }
        readersFinished.wait()
        return try handedObjects.distinctCount()
    }
}

/// Carries a read of a non-`Sendable` file onto the reader threads. Racing on
/// that file is what the test does, so the box only quiets the checker.
private struct UncheckedReader: @unchecked Sendable {
    let read: () throws -> AnyObject
}

/// The objects the readers were handed, kept alive until they are counted:
/// a mapping replaced and freed mid-round could have its address reused by
/// the next one, and two mappings would count as one.
private final class HandedObjects: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<AnyObject, any Error>] = []

    func append(_ result: Result<AnyObject, any Error>) {
        lock.lock()
        defer { lock.unlock() }
        results.append(result)
    }

    func distinctCount() throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        let objects = try results.map { try $0.get() }
        return Set(objects.map(ObjectIdentifier.init)).count
    }
}
