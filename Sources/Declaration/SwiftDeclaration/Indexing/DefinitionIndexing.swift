import Foundation
import FoundationToolbox
@_spi(Internals) import MachOCaches

/// A definition whose `index(in:)` runs through ``DefinitionIndexing``.
protocol OnceIndexedDefinition: AnyObject {
    /// Whether an indexing pass over the definition has completed.
    /// ``DefinitionIndexing`` is its only reader and writer, always inside its
    /// critical section.
    var hasCompletedIndexing: Bool { get set }
}

/// Runs a definition's indexing pass once, however many tasks ask for it at
/// the same time (evolution proposal `concurrent-definition-printing`).
///
/// A definition indexes itself on its first print, and a host may print one
/// image's definitions from several tasks at once — RuntimeViewer's display
/// path and its search corpus do, through two printers. The first caller
/// claims the definition and runs the pass on its own thread; a caller that
/// arrives meanwhile blocks on the claim's promise until the pass ends, then
/// shares its outcome: indexed, or the same error. A failed pass leaves the
/// definition unindexed, so the next call tries again.
///
/// Blocking instead of suspending cannot deadlock as long as two things stay
/// true:
/// - A pass is synchronous, so its claimer is never suspended between the
///   claim and the fulfillment — the compiler holds this one.
/// - A pass never indexes another definition. It reads the image through the
///   `SharedCache` family, and every such cache lives in a module below this
///   one, so no cache build can reach a definition either. Claiming or
///   waiting from a thread that is running a pass traps rather than risk a
///   wait cycle.
///
/// One process-wide lock covers every definition: it guards the table of
/// passes in flight and each definition's `hasCompletedIndexing`, and is held
/// only to read or flip that state. A lock per definition would cost a heap
/// allocation per definition, which the declaration model was slimmed to
/// avoid (evolution proposal `declaration-model-descriptor-slimming`).
enum DefinitionIndexing {
    private typealias Promise = SharedCacheBuildPromise<Result<Void, any Error>>

    private enum Claim {
        case alreadyIndexed
        case waitForPass(Promise)
        case runPass(Promise)
    }

    /// The passes in flight, by definition — and the lock every definition's
    /// `hasCompletedIndexing` is read and written under.
    @Mutex
    private static var promisesByDefinition: [ObjectIdentifier: Promise] = [:]

    static func isIndexed(_ definition: some OnceIndexedDefinition) -> Bool {
        _promisesByDefinition.withLockUnchecked { _ in
            definition.hasCompletedIndexing
        }
    }

    /// Runs `pass` over `definition` unless it has completed one already;
    /// waits for the pass another caller is running instead of starting a
    /// second one.
    static func index(_ definition: some OnceIndexedDefinition, runningPass pass: () throws -> Void) throws {
        let definitionIdentifier = ObjectIdentifier(definition)
        let claim: Claim = _promisesByDefinition.withLockUnchecked { promisesByDefinition in
            if definition.hasCompletedIndexing {
                return .alreadyIndexed
            }
            precondition(
                !promisesByDefinition.values.contains { $0.isBuilderCurrentThread },
                "DefinitionIndexing: an indexing pass asked to index a definition — waiting here could form a cycle; a pass must read the image, never index"
            )
            if let promise = promisesByDefinition[definitionIdentifier] {
                return .waitForPass(promise)
            }
            let promise = Promise()
            promisesByDefinition[definitionIdentifier] = promise
            return .runPass(promise)
        }

        switch claim {
        case .alreadyIndexed:
            return
        case .waitForPass(let promise):
            guard let passResult = promise.wait() else {
                preconditionFailure("DefinitionIndexing: a pass is fulfilled with its result, never with nil")
            }
            try passResult.get()
        case .runPass(let promise):
            let passResult = Result<Void, any Error> { try pass() }
            _promisesByDefinition.withLockUnchecked { promisesByDefinition in
                if case .success = passResult {
                    definition.hasCompletedIndexing = true
                }
                promisesByDefinition[definitionIdentifier] = nil
            }
            promise.fulfill(passResult)
            try passResult.get()
        }
    }
}
