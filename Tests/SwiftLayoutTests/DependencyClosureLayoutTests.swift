import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Validates the dependency-closure phase: field types, superclasses and
/// protocols that live in *other* images now resolve, closing the cross-module
/// partials the single-image engine left behind.
///
/// Two independent ground truths back the assertions:
///   - `DistributedActorTest` has a non-empty runtime field-offset vector
///     (`[16, 112, 128]`), so its closure-computed offsets are checked against
///     the runtime accessor — a fully automatic cross-module validation that
///     also exercises resolving a cross-module struct field
///     (`Distributed.LocalTestingActorID`).
///   - The two resilient subclasses have an *empty* runtime vector (their field
///     offsets are computed at runtime and stored only in the live metadata,
///     with no static `…Wvd` field-offset global emitted), so they are pinned
///     to literals derived from the cross-module parent's statically-computed
///     instance size: `ResilientBase` is a Swift root class with one stored
///     `Int` → instance size 24, so `ResilientChild.extraField` is at 24;
///     `Object` is an empty Swift root class → instance size 16, so
///     `ResilientObjCStubChild.stubField` is at 16.
@Suite
final class DependencyClosureLayoutTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    /// The on-disk path to the `SymbolTestsHelper` framework binary, derived
    /// from this test file's location (a sibling of `SymbolTestsCore` under the
    /// fixture's DerivedData). A `MachOFile`'s `imagePath` is its install name
    /// (`@rpath/…`), not a filesystem path, so the explicit search path must be
    /// computed here rather than from the loaded root.
    private static let symbolTestsHelperOnDiskPath: String = {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/SwiftLayoutTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
        return repositoryRoot
            .appendingPathComponent("Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTestsHelper.framework/Versions/A/SymbolTestsHelper")
            .standardizedFileURL.path
    }()

    private static let distributedActorTestName = "SymbolTestsCore.DistributedActors.DistributedActorTest"
    private static let resilientChildName = "SymbolTestsCore.ResilientClassFixtures.ResilientChild"
    private static let resilientObjCStubChildName = "SymbolTestsCore.ObjCResilientStubFixtures.ResilientObjCStubChild"

    /// The complete, fully-computed field-offset vectors every cross-module type
    /// must produce once the closure resolves its out-of-image dependencies.
    private static let expectedClosureFieldOffsets: [String: [Int]] = [
        distributedActorTestName: [16, 112, 128],
        resilientChildName: [24],
        resilientObjCStubChildName: [16],
    ]

    // MARK: - Low-level closure (hand-fed dependency)

    /// The low-level `dependencyClosure(root:dependencyImages:)` factory, fed
    /// exactly one dependency image, resolves a cross-module superclass —
    /// without scanning the whole transitive OS closure. Targets the two
    /// resilient subclasses whose parents live in `SymbolTestsHelper`.
    @MainActor
    @Test func lowLevelClosureResolvesCrossModuleSuperclass() async throws {
        let machO = machOImage
        guard let helperImage = MachOImage(name: "SymbolTestsHelper") else {
            Issue.record("SymbolTestsHelper must be loaded in-process for the fixture")
            return
        }
        let universe = try ImageUniverse.dependencyClosure(root: machO, dependencyImages: [helperImage])
        let calculator = StaticLayoutCalculator(imageUniverse: universe)

        for typeName in [Self.resilientChildName, Self.resilientObjCStubChildName] {
            let aggregate = try fieldLayout(ofQualifiedTypeName: typeName, with: calculator, in: machO)
            assertFullyComputed(aggregate, equals: Self.expectedClosureFieldOffsets[typeName]!, typeName: typeName)
        }
    }

    // MARK: - In-process transitive closure

    /// The in-process convenience factory resolves every cross-module partial:
    /// the distributed actor's struct field (checked against the runtime vector)
    /// and both resilient subclasses' superclasses.
    @MainActor
    @Test func inProcessClosureResolvesAllCrossModuleTypes() async throws {
        let machO = machOImage
        let universe = try ImageUniverse.dependencyClosure(root: machO)
        #expect(universe.dependencyImageCount > 0, "the closure must collect dependency images")
        let calculator = StaticLayoutCalculator(imageUniverse: universe)

        for (typeName, expectedOffsets) in Self.expectedClosureFieldOffsets {
            let aggregate = try fieldLayout(ofQualifiedTypeName: typeName, with: calculator, in: machO)
            assertFullyComputed(aggregate, equals: expectedOffsets, typeName: typeName)
        }

        // Independent ground truth: the distributed actor's runtime field-offset
        // vector (non-empty) must match the closure-computed offsets exactly.
        let runtimeOffsets = try runtimeFieldOffsets(ofQualifiedTypeName: Self.distributedActorTestName, in: machO)
        #expect(
            runtimeOffsets == Self.expectedClosureFieldOffsets[Self.distributedActorTestName],
            "DistributedActorTest runtime vector \(String(describing: runtimeOffsets)) must match the pinned closure offsets"
        )
    }

    /// Regression guard: the single-image engine leaves these three types
    /// partial (a cross-module field/superclass it cannot reach), so the closure
    /// is demonstrably what resolves them.
    @MainActor
    @Test func singleImageEngineLeavesCrossModuleTypesPartial() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)
        for typeName in Self.expectedClosureFieldOffsets.keys {
            let aggregate = try fieldLayout(ofQualifiedTypeName: typeName, with: calculator, in: machO)
            let isFullyComputed = aggregate.fields.allSatisfy {
                if case .computed = $0.resolution { return true } else { return false }
            }
            #expect(!isFullyComputed, "\(typeName) is expected to be partial under the single-image engine")
        }
    }

    // MARK: - Offline closure (MachOFile)

    /// The offline `MachOFile` convenience factory resolves cross-module types
    /// with no running process: the two resilient subclasses through an explicit
    /// on-disk `SymbolTestsHelper` path, and the distributed actor's struct
    /// field through the system dyld shared cache (`Distributed`). The resilient
    /// classes are pinned to the same literals; `DistributedActorTest` is pinned
    /// to the vector verified against the runtime in
    /// `inProcessClosureResolvesAllCrossModuleTypes`.
    @MainActor
    @Test func offlineClosureResolvesCrossModuleTypes() async throws {
        let rootFile = machOFile
        let universe = try ImageUniverse.dependencyClosure(
            root: rootFile,
            searchPaths: [.machOFile(path: Self.symbolTestsHelperOnDiskPath), .systemDyldSharedCache]
        )
        let calculator = StaticLayoutCalculator(imageUniverse: universe)

        for (typeName, expectedOffsets) in Self.expectedClosureFieldOffsets {
            let aggregate = try fieldLayout(ofQualifiedTypeName: typeName, with: calculator, in: rootFile)
            assertFullyComputed(aggregate, equals: expectedOffsets, typeName: typeName)
        }
    }

    // MARK: - Helpers

    private func fieldLayout<MachO: MachOSwiftSectionRepresentableWithCache>(
        ofQualifiedTypeName qualifiedTypeName: String,
        with calculator: StaticLayoutCalculator<MachO>,
        in machO: MachO
    ) throws -> AggregateFieldLayout {
        for contextDescriptor in try machO.swift.contextDescriptors {
            guard let descriptor = contextDescriptor.typeContextDescriptorWrapper else { continue }
            guard descriptor.isStruct || descriptor.isClass else { continue }
            guard
                let name = (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
                name == qualifiedTypeName
            else { continue }
            return try calculator.fieldLayout(of: descriptor)
        }
        Issue.record("type \(qualifiedTypeName) not found in fixture")
        throw LayoutResolutionError.unknown(.typeDescriptorNotFound(qualifiedTypeName: qualifiedTypeName))
    }

    private func runtimeFieldOffsets(ofQualifiedTypeName qualifiedTypeName: String, in machO: MachOImage) throws -> [Int]? {
        for contextDescriptor in try machO.swift.contextDescriptors {
            guard let descriptor = contextDescriptor.typeContextDescriptorWrapper else { continue }
            guard
                let name = (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
                name == qualifiedTypeName,
                let accessor = try descriptor.typeContextDescriptor.metadataAccessorFunction(in: machO)
            else { continue }
            let response = try accessor(request: .init())
            let metadata = try response.value.resolve(in: machO)
            switch metadata {
            case .struct(let structMetadata):
                return try structMetadata.fieldOffsets(in: machO).map { Int($0) }
            case .class(let classMetadata):
                return try classMetadata.fieldOffsets(in: machO).map { Int($0) }
            default:
                return nil
            }
        }
        return nil
    }

    private func assertFullyComputed(
        _ aggregate: AggregateFieldLayout,
        equals expectedOffsets: [Int],
        typeName: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let unresolved = aggregate.fields.compactMap { field -> String? in
            if case .unknown(let reason) = field.resolution { return "\(field.fieldName):\(reason)" }
            return nil
        }
        #expect(unresolved.isEmpty, "\(typeName) has unresolved fields: \(unresolved)", sourceLocation: sourceLocation)
        #expect(
            aggregate.computedFieldOffsets == expectedOffsets,
            "\(typeName): computed \(aggregate.computedFieldOffsets) != expected \(expectedOffsets)",
            sourceLocation: sourceLocation
        )
    }
}
