import Foundation
import Testing
import MachOKit
import MachOFixtureSupport
@testable import MachOTestingSupport
@_spi(Support) import SwiftIndexing
import SwiftInspection
import SwiftDeclarationRendering
@testable @_spi(Support) import SwiftPrivateDiscriminators

/// An image's private discriminators, recovered from candidates the image's
/// own names make (evolution proposal `private-declarations`).
///
/// Nothing here depends on the system the tests run on; the suite reading the
/// running system's images is `PrivateDiscriminatorSourceFileSystemImageTests`.
@Suite(.serialized, ExclusiveImageAccess(LocalTypeFixture.exclusiveAccessName))
struct PrivateDiscriminatorSourceFileIndexTests {
    /// The fixture is compiled from `Fixture.swift`, and its names spell
    /// `Fixture` (`LocalTypeFixtureVisitor`). `md5 -s
    /// 'LocalTypeFixtureUnstrippedFixture.swift'`, computed outside this code
    /// base, is `2ea5a000e301e8e89be43d5fb26a4d0e`.
    private static let unstrippedFixtureDiscriminator = "_2EA5A000E301E8E89BE43D5FB26A4D0E"

    private static let swiftUICorePath = "/System/Library/Frameworks/SwiftUICore.framework/Versions/A/SwiftUICore"

    /// `md5 -s 'SwiftUICoreEnabled.swift'`.
    private static let enabledDiscriminator = "_09CE35833F3876FE3A3A46977D61FC64"

    /// No candidate the names below make produces it.
    private static let unrecoverableDiscriminator = "_70EED0686586E4A728468B96DBF4A6DF"

    private static let enabledSourceFile = PrivateDiscriminatorSourceFiles.SourceFile(fileName: "Enabled.swift", moduleName: "SwiftUICore", isSynthesized: false)

    /// Two names of SwiftUICore's, as its indexer prints them: under the ABI
    /// module name `SwiftUI`.
    private static let swiftUICoreNames: [PrivateDiscriminatorSourceFiles.ImageName] = [
        .init(printedName: "SwiftUI.EnabledKey", discriminators: [enabledDiscriminator]),
        .init(printedName: "SwiftUI.NearestScrollableAxesEnvironmentKey", discriminators: [unrecoverableDiscriminator]),
    ]

    /// The size of a large-stack worker's stack, which reading the names
    /// needs: `StackSafeExecutor.largeStackThreadSize`.
    private static let largeStackSize = 8 * 1024 * 1024

    /// The discriminator of the private `hiddenValues()`, which declares the
    /// local type `Hidden`, read off the indexed name of that type.
    private static func hiddenValuesDiscriminator<MachO>(in indexer: SwiftDeclarationIndexer<MachO>) throws -> String {
        let hidden = try #require(indexer.allTypeDefinitions.keys.first { $0.node.localTypeNaming != nil && $0.name.hasPrefix("Hidden #1 in ") })
        return try #require(hidden.node.privateDeclarations.first).discriminator
    }

    @Test func fileImageRecoversTheFixtureSourceFile() async throws {
        let machOFile = try LocalTypeFixture.machOFile(.unstripped)
        let indexer = SwiftDeclarationIndexer(configuration: .init(), eventHandlers: [], in: machOFile)
        try await indexer.prepare()
        let discriminator = try Self.hiddenValuesDiscriminator(in: indexer)

        #expect(discriminator == Self.unstrippedFixtureDiscriminator)
        let sourceFiles = PrivateDiscriminatorSourceFileIndex(indexer: indexer, knownFileNames: []).sourceFiles(forDiscriminators: [discriminator])
        #expect(sourceFiles == [discriminator: .init(fileName: "Fixture.swift", moduleName: "LocalTypeFixtureUnstripped", isSynthesized: false)])
    }

    @Test func loadedImageRecoversTheFixtureSourceFile() async throws {
        let machOImage = try LocalTypeFixture.loadedImage(.unstripped)
        let indexer = SwiftDeclarationIndexer(configuration: .init(), eventHandlers: [], in: machOImage)
        try await indexer.prepare()
        let discriminator = try Self.hiddenValuesDiscriminator(in: indexer)

        let sourceFiles = PrivateDiscriminatorSourceFileIndex(indexer: indexer, knownFileNames: []).sourceFiles(forDiscriminators: [discriminator])
        #expect(sourceFiles == [discriminator: .init(fileName: "Fixture.swift", moduleName: "LocalTypeFixtureUnstripped", isSynthesized: false)])
    }

    /// The image's names are read on the first request, and only then; a
    /// discriminator nothing produces is left out of every answer, and is
    /// not searched for again.
    @Test func namesAreReadOnceAndAnswersKept() {
        let readCount = ReadCount()
        let index = PrivateDiscriminatorSourceFileIndex(imagePath: Self.swiftUICorePath, knownFileNames: []) {
            readCount.increment()
            return Self.swiftUICoreNames
        }
        #expect(readCount.value == 0)

        #expect(index.sourceFiles(forDiscriminators: [Self.enabledDiscriminator, Self.unrecoverableDiscriminator]) == [Self.enabledDiscriminator: Self.enabledSourceFile])
        #expect(index.searchCount == 1)
        #expect(index.sourceFiles(forDiscriminators: [Self.unrecoverableDiscriminator]).isEmpty)
        #expect(index.sourceFiles(forDiscriminators: [Self.enabledDiscriminator]) == [Self.enabledDiscriminator: Self.enabledSourceFile])
        #expect(readCount.value == 1)
        #expect(index.searchCount == 1)
    }

    /// Reading the names prints every name the image declares, and a request
    /// comes from wherever the host is — a cooperative thread's 512 KB stack
    /// here. The names are read on a large stack all the same.
    @Test func namesAreReadOnALargeStack() async throws {
        let requestingStackSize = pthread_get_stacksize_np(pthread_self())
        try #require(requestingStackSize < Self.largeStackSize, "the premise: the request comes from a small stack, not \(requestingStackSize) bytes")
        let readingStackSizes = ReadingStackSizes()
        let index = PrivateDiscriminatorSourceFileIndex(imagePath: Self.swiftUICorePath, knownFileNames: []) {
            readingStackSizes.append(pthread_get_stacksize_np(pthread_self()))
            return Self.swiftUICoreNames
        }

        #expect(index.sourceFiles(forDiscriminators: [Self.enabledDiscriminator]) == [Self.enabledDiscriminator: Self.enabledSourceFile])
        let stackSizes = readingStackSizes.values
        #expect(stackSizes.count == 1)
        #expect(stackSizes.allSatisfy { $0 >= Self.largeStackSize }, "the names were read on stacks of \(stackSizes) bytes")
    }

    /// The names are read outside the index's lock: two first requests that
    /// overlap both read them — each waits in the names closure until the
    /// other is there too — agree, and search once.
    @Test func overlappingFirstRequestsBothReadAndSearchOnce() async throws {
        let readCount = ReadCount()
        let rendezvous = Rendezvous(expectedArrivals: 2)
        let index = PrivateDiscriminatorSourceFileIndex(imagePath: Self.swiftUICorePath, knownFileNames: []) {
            readCount.increment()
            // Times out instead of hanging when the other request cannot get
            // here — which is what a lock held across the read does.
            _ = rendezvous.arriveAndWait(timeout: 10)
            return Self.swiftUICoreNames
        }

        let answers = await Self.onThreadsOfTheirOwn(2) {
            index.sourceFiles(forDiscriminators: [Self.enabledDiscriminator, Self.unrecoverableDiscriminator])
        }
        #expect(answers == Array(repeating: [Self.enabledDiscriminator: Self.enabledSourceFile], count: 2))
        #expect(readCount.value == 2)
        #expect(index.searchCount == 1)
    }

    /// A printer naming the file of every private declaration it shows
    /// searches once for the whole image (evolution proposal
    /// `private-declaration-source-files`), and every answer after that is a
    /// lookup — the same answer a request of its own gets.
    @Test func wholeImageIsSearchedOnceAndAnsweredFromThen() async throws {
        let indexer = SwiftDeclarationIndexer(configuration: .init(), eventHandlers: [], in: try LocalTypeFixture.machOFile(.unstripped))
        try await indexer.prepare()
        let index = PrivateDiscriminatorSourceFileIndex(indexer: indexer, knownFileNames: [])

        index.recoverSourceFiles(ofEveryDeclarationIn: indexer)
        #expect(index.searchCount == 1)

        #expect(index.sourceFile(forPrivateDiscriminator: Self.unstrippedFixtureDiscriminator) == PrivateDeclarationSourceFile(fileName: "Fixture.swift", moduleName: "LocalTypeFixtureUnstripped", isSynthesized: false))
        #expect(index.sourceFile(forPrivateDiscriminator: try Self.hiddenValuesDiscriminator(in: indexer)) != nil)
        #expect(index.searchCount == 1)
    }

    /// What the whole-image search found is what a printer is told, and what
    /// it did not find reads as not recovered rather than being searched for
    /// again.
    @Test func providerAnswersWhatTheSearchFound() {
        let index = PrivateDiscriminatorSourceFileIndex(imagePath: Self.swiftUICorePath, knownFileNames: []) { Self.swiftUICoreNames }
        #expect(index.sourceFile(forPrivateDiscriminator: Self.enabledDiscriminator) == PrivateDeclarationSourceFile(fileName: "Enabled.swift", moduleName: "SwiftUICore", isSynthesized: false))
        #expect(index.sourceFile(forPrivateDiscriminator: Self.unrecoverableDiscriminator) == nil)
        #expect(index.sourceFile(forPrivateDiscriminator: Self.unrecoverableDiscriminator) == nil)
        #expect(index.searchCount == 2)
    }

    /// The indexer's deinit is what releases the image's caches
    /// (`SharedCacheRegistry`), and a host keeps the index as long as the
    /// image: once the names are read, the index lets go of the indexer.
    @Test func indexLetsGoOfItsIndexerOnceTheNamesAreRead() async throws {
        let (index, indexer) = try await Self.indexHoldingTheOnlyReferenceToItsIndexer()
        #expect(indexer.object != nil, "the premise: until the first request, the index holds the indexer")

        #expect(index.sourceFiles(forDiscriminators: [Self.unstrippedFixtureDiscriminator]) == [
            Self.unstrippedFixtureDiscriminator: .init(fileName: "Fixture.swift", moduleName: "LocalTypeFixtureUnstripped", isSynthesized: false),
        ])
        #expect(try await indexer.isReleased(within: 2), "the index still holds its indexer")
    }

    private static func indexHoldingTheOnlyReferenceToItsIndexer() async throws -> (PrivateDiscriminatorSourceFileIndex, WeakReference<SwiftDeclarationIndexer<MachOFile>>) {
        let indexer = SwiftDeclarationIndexer(configuration: .init(), eventHandlers: [], in: try LocalTypeFixture.machOFile(.unstripped))
        try await indexer.prepare()
        return (PrivateDiscriminatorSourceFileIndex(indexer: indexer, knownFileNames: []), WeakReference(indexer))
    }

    /// Runs `body` on `count` threads started for it, all at once, and
    /// returns what each returned. Threads of their own, not tasks: two
    /// tasks are not sure to run at once on a busy cooperative pool.
    private static func onThreadsOfTheirOwn<Result: Sendable>(_ count: Int, _ body: @escaping @Sendable () -> Result) async -> [Result] {
        await withCheckedContinuation { continuation in
            let results = ResultCollector<Result>(expectedCount: count) { continuation.resume(returning: $0) }
            for _ in 0 ..< count {
                Thread { results.append(body()) }.start()
            }
        }
    }
}

private final class ReadCount: @unchecked Sendable {
    private let lock = NSLock()

    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }
}

private final class ReadingStackSizes: @unchecked Sendable {
    private let lock = NSLock()

    private var stackSizes: [Int] = []

    var values: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return stackSizes
    }

    func append(_ stackSize: Int) {
        lock.lock()
        defer { lock.unlock() }
        stackSizes.append(stackSize)
    }
}

/// Holds every caller until `expectedArrivals` have arrived.
private final class Rendezvous: @unchecked Sendable {
    private let condition = NSCondition()

    private let expectedArrivals: Int

    private var arrivals = 0

    init(expectedArrivals: Int) {
        self.expectedArrivals = expectedArrivals
    }

    /// Whether every expected caller arrived within `timeout` seconds.
    func arriveAndWait(timeout: TimeInterval) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        arrivals += 1
        condition.broadcast()
        let deadline = Date(timeIntervalSinceNow: timeout)
        while arrivals < expectedArrivals {
            if !condition.wait(until: deadline) {
                return arrivals >= expectedArrivals
            }
        }
        return true
    }
}

/// Collects the results of `expectedCount` threads and hands them over once
/// the last is in.
private final class ResultCollector<Result: Sendable>: @unchecked Sendable {
    private let lock = NSLock()

    private let expectedCount: Int

    private let completion: @Sendable ([Result]) -> Void

    private var results: [Result] = []

    init(expectedCount: Int, completion: @escaping @Sendable ([Result]) -> Void) {
        self.expectedCount = expectedCount
        self.completion = completion
    }

    func append(_ result: Result) {
        lock.lock()
        results.append(result)
        let completedResults = results.count == expectedCount ? results : nil
        lock.unlock()
        if let completedResults {
            completion(completedResults)
        }
    }
}

private final class WeakReference<Object: AnyObject>: @unchecked Sendable {
    private(set) weak var object: Object?

    init(_ object: Object) {
        self.object = object
    }

    /// Whether the object is gone within `timeout` seconds. The last
    /// reference to a closure run on a large stack can sit with the worker
    /// that ran it for a moment after the call that submitted it returns.
    func isReleased(within timeout: TimeInterval) async throws -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while object != nil {
            guard Date() < deadline else { return false }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return true
    }
}
