@_spi(Support) @testable import SwiftSpecialization
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
import Foundation
import Testing
import MachOKit
import Dependencies
@_spi(Internals) import MachOSymbols
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// `IndexerConformanceProvider` builds its class hierarchy on a large stack.
///
/// The build demangles every indexed class's superclass and prints two names
/// per class. A host calls the specializer synchronously — RuntimeViewer from
/// an actor, on a 512 KB cooperative thread — and on such a thread each of
/// those calls hopped to a large-stack worker on its own, with the provider's
/// lock held throughout. The build has to move to a large stack in one hop
/// instead, before it takes the lock.
///
/// The one piece of code a test can run inside the build is an event handler:
/// a class whose wrapper cannot be materialized is reported from the walk
/// itself (`SubclassMapMaterializationFailureTests` injects the same unreadable
/// class). The handler records the stack of the thread it is called on.
@Suite
final class ClassHierarchyBuildStackTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    private static let largeStackSize = 8 * 1024 * 1024

    private func typeName(named leafName: String, in indexer: SwiftDeclarationIndexer<MachOFile>) throws -> TypeName {
        try #require(indexer.allTypeDefinitions.keys.first { $0.declaredNameForTesting == leafName })
    }

    @Test func classHierarchyIsBuiltOnALargeStack() async throws {
        let recorder = SubclassMapReportStackRecorder()
        let unsafeMachOFile = machOFile
        let indexer = SwiftDeclarationIndexer(eventHandlers: [recorder], in: unsafeMachOFile)
        try await indexer.prepare()

        let baseClassName = try typeName(named: "ClassTest", in: indexer)
        let donorTypeName = try typeName(named: "FinalClassTest", in: indexer)
        let donorDefinition = try #require(indexer.allTypeDefinitions[donorTypeName])
        guard case .class(let realClassDescriptor) = donorDefinition.typeContextDescriptorWrapper else {
            Issue.record("FinalClassTest is expected to be a class")
            return
        }
        // A real class descriptor's layout re-wrapped far past the fixture's
        // end of file, so materializing its wrapper throws inside the build.
        indexer.currentStorage.allTypeDefinitions[donorTypeName] = TypeDefinition(
            typeContextDescriptorWrapper: .class(ClassDescriptor(layout: realClassDescriptor.layout, offset: 0x0FFF_FFF0)),
            typeName: donorTypeName,
            isSpecialized: false
        )
        indexer.allStorageCache = .init()

        // The caller gets a cooperative thread's stack explicitly, so the test
        // does not depend on which thread Swift Testing runs its body on. The
        // body suspends instead of blocking while the thread works.
        let provider = IndexerConformanceProvider(indexer: indexer)
        let callerStackSize = await withCheckedContinuation { continuation in
            let callerThread = Thread {
                let callerStackSize = pthread_get_stacksize_np(pthread_self())
                _ = provider.subclasses(of: baseClassName)
                continuation.resume(returning: callerStackSize)
            }
            callerThread.stackSize = 512 * 1024
            callerThread.start()
        }
        try #require(callerStackSize < Self.largeStackSize, "the caller must have a small stack for the test to mean anything; it has \(callerStackSize) bytes")

        let reportingStackSizes = recorder.stackSizes
        try #require(!reportingStackSizes.isEmpty, "the unreadable class must be reported from inside the build")
        #expect(
            reportingStackSizes.allSatisfy { $0 >= Self.largeStackSize },
            "the build ran on stacks of \(reportingStackSizes) bytes; called from a \(callerStackSize)-byte stack it must move to a large one"
        )
    }
}

/// Records the stack size of every thread that reports a subclass-map
/// degradation. Event handlers run on the dispatching thread.
private final class SubclassMapReportStackRecorder: SwiftIndexEvents.Handler, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedStackSizes: [Int] = []

    func handle(event: SwiftIndexEvents.Payload) {
        guard case .renderingDegraded(let context, _) = event, case .subclassMap = context.source else { return }
        let stackSize = pthread_get_stacksize_np(pthread_self())
        lock.lock()
        defer { lock.unlock() }
        recordedStackSizes.append(stackSize)
    }

    var stackSizes: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return recordedStackSizes
    }
}
