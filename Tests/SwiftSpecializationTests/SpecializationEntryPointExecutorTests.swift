@_spi(Support) @testable import SwiftSpecialization
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
import Foundation
import Testing
import MachOKit
import Demangling
@_spi(Internals) import MachOSymbols
@testable import MachOSwiftSection
import MachOTestingSupport

/// The async `TypeDefinition.specialize` overloads are library entry points,
/// so their bodies run on the large-stack task executor like every other
/// async entry point's (`LargeStackTaskExecution.run`). Without it, a body
/// called from a cooperative thread — RuntimeViewer calls the deriving
/// overload from an actor — runs on that thread's 512 KB stack, where every
/// demangle and print hops to a large-stack worker on its own, among them the
/// ones `DependentMemberProjection` makes under its per-image lock.
///
/// The conformance provider is the code a test can run inside the body:
/// deriving a nested type asks the specializer for the nested type's request,
/// and the request asks the provider for candidates. A stand-in provider
/// records the stack of every thread it is asked on.
@Suite
struct SpecializationEntryPointExecutorTests {
    private static let largeStackSize = 8 * 1024 * 1024

    @Test(.enabled(if: LargeStackTaskExecution.isEnabled && LargeStackTaskExecution.isSupported))
    func runtimeDerivingSpecializationRunsOnTheLargeStackExecutor() async throws {
        let indexer = try await GenericSpecializationFixtureIndexers.shared.runtime()
        let definition = try GenericSpecializationFixtureIndexers.typeDefinition(named: "NestedHost", in: indexer)
        let recordingProvider = StackRecordingConformanceProvider(wrapping: IndexerConformanceProvider(indexer: indexer))
        let specializer = GenericSpecializer(machO: indexer.machO, conformanceProvider: recordingProvider, indexer: indexer)
        let request = try specializer.makeRequest(for: definition.typeContextDescriptorWrapper)
        let selection: SpecializationSelection = ["A": .metatype(Int.self)]
        let result = try specializer.specialize(request, with: selection)
        let intNode = try await demangleAsNode("Si", isType: true)
        recordingProvider.removeRecordedStackSizes()

        let specialized = try await definition.specialize(
            with: result,
            typeArgumentNodes: [intNode],
            derivingNestedSpecializationsWith: specializer,
            selection: selection,
            typeArgumentNodesByParameter: ["A": intNode],
            in: indexer.machO
        )

        try #require(!specialized.typeChildren.isEmpty, "the fixture's nested type must be derived, or the provider is never asked")
        try expectOnlyLargeStacks(recordingProvider.recordedStackSizes)
    }

    @Test(.enabled(if: LargeStackTaskExecution.isEnabled && LargeStackTaskExecution.isSupported))
    func offlineDerivingSpecializationRunsOnTheLargeStackExecutor() async throws {
        let indexer = try await GenericSpecializationFixtureIndexers.shared.offline()
        let definition = try GenericSpecializationFixtureIndexers.typeDefinition(named: "NestedHost", in: indexer)
        let recordingProvider = StackRecordingConformanceProvider(wrapping: IndexerConformanceProvider(indexer: indexer))
        let specializer = GenericSpecializer(machO: indexer.machO, conformanceProvider: recordingProvider, indexer: indexer)
        let request = try specializer.makeRequest(for: definition.typeContextDescriptorWrapper)
        let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])
        recordingProvider.removeRecordedStackSizes()

        let specialized = try await definition.specialize(
            with: result,
            derivingNestedSpecializationsWith: specializer,
            in: indexer.machO
        )

        try #require(!specialized.typeChildren.isEmpty, "the fixture's nested type must be derived, or the provider is never asked")
        try expectOnlyLargeStacks(recordingProvider.recordedStackSizes)
    }

    private func expectOnlyLargeStacks(_ stackSizes: [Int]) throws {
        try #require(!stackSizes.isEmpty, "deriving the nested type must ask the provider for candidates")
        #expect(
            stackSizes.allSatisfy { $0 >= Self.largeStackSize },
            "the provider was asked on stacks of \(Set(stackSizes).sorted()) bytes; the specialization's body must run on the large-stack executor"
        )
    }
}

/// Forwards every question to a real provider and records the stack size of
/// the thread each one was asked on.
private final class StackRecordingConformanceProvider: ConformanceProvider, @unchecked Sendable {
    private let wrappedProvider: any ConformanceProvider
    private let lock = NSLock()
    private var stackSizes: [Int] = []

    init(wrapping wrappedProvider: any ConformanceProvider) {
        self.wrappedProvider = wrappedProvider
    }

    var recordedStackSizes: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return stackSizes
    }

    func removeRecordedStackSizes() {
        lock.lock()
        defer { lock.unlock() }
        stackSizes.removeAll()
    }

    private func recordCurrentThreadStackSize() {
        let stackSize = pthread_get_stacksize_np(pthread_self())
        lock.lock()
        defer { lock.unlock() }
        stackSizes.append(stackSize)
    }

    func types(conformingTo protocolName: ProtocolName) -> [TypeName] {
        recordCurrentThreadStackSize()
        return wrappedProvider.types(conformingTo: protocolName)
    }

    func doesType(_ typeName: TypeName, conformTo protocolName: ProtocolName) -> Bool {
        recordCurrentThreadStackSize()
        return wrappedProvider.doesType(typeName, conformTo: protocolName)
    }

    func conformances(of typeName: TypeName) -> [ProtocolName] {
        recordCurrentThreadStackSize()
        return wrappedProvider.conformances(of: typeName)
    }

    var allTypeNames: [TypeName] {
        recordCurrentThreadStackSize()
        return wrappedProvider.allTypeNames
    }

    func typeDefinition(for typeName: TypeName) -> TypeDefinition? {
        recordCurrentThreadStackSize()
        return wrappedProvider.typeDefinition(for: typeName)
    }

    func imagePath(for typeName: TypeName) -> String? {
        recordCurrentThreadStackSize()
        return wrappedProvider.imagePath(for: typeName)
    }

    func subclasses(of baseClassName: TypeName) -> [TypeName] {
        recordCurrentThreadStackSize()
        return wrappedProvider.subclasses(of: baseClassName)
    }

    func superclassLink(of className: TypeName) -> SuperclassLink {
        recordCurrentThreadStackSize()
        return wrappedProvider.superclassLink(of: className)
    }

    func isConditionalConformance(of typeName: TypeName, to protocolName: ProtocolName) -> Bool {
        recordCurrentThreadStackSize()
        return wrappedProvider.isConditionalConformance(of: typeName, to: protocolName)
    }
}
