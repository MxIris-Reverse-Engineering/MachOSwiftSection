import Foundation
import MachOFixtureSupport
import Testing

/// Serializes every test that declares the same fixture image — **across
/// suites and across test targets**.
///
/// `.serialized` cannot do this. Its documentation is explicit: it "does not
/// affect the execution of a test relative to its peers or to unrelated tests",
/// so it orders tests *within* one container and nothing more. A whole-process
/// resource like a per-image cache needs ordering between containers.
///
/// A global actor cannot do it either. These tests are `async`, and `await`
/// suspends and yields the actor: an actor guarantees no *concurrent* execution,
/// not the absence of *interleaving*, so a sibling test resumes in the middle of
/// one that is mid-way through clearing and re-checking a cache. `TestScoping`
/// wraps the entire test body, suspension points included, which is the one
/// primitive that gives a real critical section.
///
/// Apply it to every suite that touches the image, not just the one making the
/// assertions — an exclusion held by one side is not an exclusion:
///
///     @Suite(.serialized, ExclusiveImageAccess(.SymbolTestsHelper))
///     final class PerImageCacheEvictionTests: MachOFileTests { … }
///
///     @Suite(ExclusiveImageAccess(.SymbolTestsHelper))
///     final class DependencyClosureLayoutTests: MachOSwiftSectionFixtureTests { … }
///
/// It also makes the sharing *greppable*, which is the failure this exists to
/// prevent. `PerImageCacheEvictionTests` documented in prose that it ran against
/// "an image no other suite indexes"; that was true of every suite naming the
/// image through `MachOFileName`, and false in fact, because
/// `DependencyClosureLayoutTests` reached the same binary by building its path
/// by hand. Searching for the fixture case name could not find it. Searching for
/// `ExclusiveImageAccess` finds every declared user.
public struct ExclusiveImageAccess: TestTrait, SuiteTrait, TestScoping {
    private let imageName: String

    public init(_ imageName: String) {
        self.imageName = imageName
    }

    /// Applied to a suite, this must reach the suite's tests — the scope is
    /// provided per test function, never at the suite level (verified against
    /// the 6.3.3 runtime: `provideScope` is called only for functions, so the
    /// non-reentrant lock below cannot nest with itself).
    public var isRecursive: Bool { true }

    public func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: () async throws -> Void
    ) async throws {
        try await FixtureImageExclusion.withExclusiveAccess(to: imageName, performing: function)
    }
}

/// Runs `body` while holding the image, then releases it.
///
/// Free-standing rather than a method on the actor: the test body is a
/// non-`Sendable` closure, and handing it to an actor method would cross an
/// isolation boundary, which Swift 6 rejects (`sending value of non-Sendable
/// type … risks causing data races`). Only the *lock state* belongs on the
/// actor; the body stays in its caller's isolation, where the testing library
/// put it.
public enum FixtureImageExclusion {
    public static func withExclusiveAccess(
        to imageName: String,
        performing body: () async throws -> Void
    ) async rethrows {
        await FixtureImageLock.shared.acquire(imageName)
        do {
            try await body()
        } catch {
            // Release before rethrowing: leaving the image held would turn one
            // failing test into a hang for every later test that declares it.
            await FixtureImageLock.shared.release(imageName)
            throw error
        }
        await FixtureImageLock.shared.release(imageName)
    }
}

extension ExclusiveImageAccess {
    /// Spelled from the fixture case so a typo is a compile error rather than a
    /// silently ineffective exclusion. `package`, matching the fixture enums —
    /// a suite reaching the image by a hand-built path (which is how the sharing
    /// went unnoticed) uses the `String` initializer with the same key.
    package init(_ fileName: MachOFileName) {
        self.init(fileName.rawValue)
    }

    package init(_ imageName: MachOImageName) {
        self.init(imageName.rawValue)
    }
}

/// Process-wide mutual exclusion keyed on a fixture image.
///
/// Non-reentrant on purpose: a scope is only ever provided per test function
/// (never additionally at the suite level), so nesting cannot arise, and the
/// simpler invariant is easier to keep true than a reentrancy counter.
actor FixtureImageLock {
    static let shared = FixtureImageLock()

    private var busyImageNames: Set<String> = []
    private var waitersByImageName: [String: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(_ imageName: String) async {
        // A loop, not a single check: being resumed only means the previous
        // holder released. Re-acquiring the actor is itself a suspension, so a
        // newly arriving test can slip in first and take the image — at which
        // point this one waits again.
        while busyImageNames.contains(imageName) {
            await withCheckedContinuation { continuation in
                waitersByImageName[imageName, default: []].append(continuation)
            }
        }
        busyImageNames.insert(imageName)
    }

    func release(_ imageName: String) {
        busyImageNames.remove(imageName)
        guard var waiters = waitersByImageName[imageName], !waiters.isEmpty else { return }
        let next = waiters.removeFirst()
        waitersByImageName[imageName] = waiters.isEmpty ? nil : waiters
        next.resume()
    }
}
