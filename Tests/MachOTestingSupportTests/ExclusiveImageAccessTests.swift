import Foundation
import Testing
@testable import MachOTestingSupport

/// The exclusion must be demonstrated, not asserted in prose — a promise in a
/// doc comment is exactly what failed here the first time.
///
/// Both suites below carry `ExclusiveImageAccess` for the same key and run in
/// separate containers, so the testing library is free to interleave them. A
/// shared observer records every enter/exit; overlapping intervals would appear
/// as an enter arriving while another test is still inside.
@Suite
struct ExclusiveImageAccessTests {
    @Test func concurrentAcquirersOfOneImageNeverOverlap() async throws {
        let observer = OverlapObserver()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 8 {
                group.addTask {
                    await FixtureImageExclusion.withExclusiveAccess(to: "SharedImage") {
                        await observer.enter()
                        // Yield repeatedly: a lock that only excluded synchronous
                        // work — a global actor, say — lets a sibling run here.
                        for _ in 0 ..< 4 { await Task.yield() }
                        await observer.exit()
                    }
                }
            }
        }

        #expect(await observer.maximumConcurrentHolders == 1, "two tests held the same image at once")
        #expect(await observer.completedHolderCount == 8, "every acquirer must get its turn")
    }

    /// Different keys must not block each other, or the trait would serialize
    /// the whole suite tree instead of one image.
    @Test func differentImagesProceedConcurrently() async throws {
        let observer = OverlapObserver()

        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 6 {
                group.addTask {
                    await FixtureImageExclusion.withExclusiveAccess(to: "Image\(index)") {
                        await observer.enter()
                        for _ in 0 ..< 4 { await Task.yield() }
                        await observer.exit()
                    }
                }
            }
        }

        #expect(await observer.maximumConcurrentHolders > 1, "distinct images must not serialize against each other")
    }

    /// A throwing body must still release, or one failed test wedges every later
    /// one that declares the image — turning a single failure into a hang.
    @Test func releasesAfterAThrowingBody() async throws {
        struct BodyError: Error {}

        await #expect(throws: BodyError.self) {
            try await FixtureImageExclusion.withExclusiveAccess(to: "ThrowingImage") {
                throw BodyError()
            }
        }

        // Would hang rather than fail if the lock leaked.
        var reacquired = false
        await FixtureImageExclusion.withExclusiveAccess(to: "ThrowingImage") {
            reacquired = true
        }
        #expect(reacquired)
    }
}

private actor OverlapObserver {
    private var currentHolders = 0
    private(set) var maximumConcurrentHolders = 0
    private(set) var completedHolderCount = 0

    func enter() {
        currentHolders += 1
        maximumConcurrentHolders = max(maximumConcurrentHolders, currentHolders)
    }

    func exit() {
        currentHolders -= 1
        completedHolderCount += 1
    }
}
