import Foundation
import Testing
import SnapshotTesting
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport
import MachOFixtureSupport

@Suite(.serialized, .snapshots(record: .missing))
final class SymbolTestsCoreDumpSnapshotTests: MachOFileTests, SnapshotDumpableTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    /// Hand-maintained list of every @Test method in this suite.
    /// T5's coverage-invariant test compares this against the filesystem
    /// and fails loudly if they drift. Keep in sync when adding/removing tests.
    static let registeredTestMethodNames: Set<String> = [
        "actorsSnapshot",
        "associatedTypeWitnessPatternsSnapshot",
        "asyncSequenceSnapshot",
        "attributesSnapshot",
        "basicTypesSnapshot",
        "builtinTypeFieldsSnapshot",
        "classBoundGenericsSnapshot",
        "classesSnapshot",
        "codableSnapshot",
        "collectionConformancesSnapshot",
        "concurrencySnapshot",
        "conditionalConformanceVariantsSnapshot",
        "customLiteralsSnapshot",
        "defaultImplementationVariantsSnapshot",
        "deinitVariantsSnapshot",
        "dependentTypeAccessSnapshot",
        "diamondInheritanceSnapshot",
        "distributedActorsSnapshot",
        "enumsSnapshot",
        "errorTypesSnapshot",
        "existentialAnySnapshot",
        "extensionsSnapshot",
        "fieldDescriptorVariantsSnapshot",
        "functionFeaturesSnapshot",
        "functionTypesSnapshot",
        "genericFieldLayoutSnapshot",
        "genericRequirementVariantsSnapshot",
        "genericsSnapshot",
        "globalDeclarationsSnapshot",
        "initializersSnapshot",
        "keyPathsSnapshot",
        "markerProtocolsSnapshot",
        "metatypeUsageSnapshot",
        "nestedFunctionsSnapshot",
        "nestedGenericsSnapshot",
        "neverExtensionsSnapshot",
        "noncopyableSnapshot",
        "objCClassWrappersSnapshot",
        "objCResilientStubsSnapshot",
        "opaqueReturnTypesSnapshot",
        "operatorsSnapshot",
        "optionSetAndRawRepresentableSnapshot",
        "overloadedMembersSnapshot",
        "propertyWrapperVariantsSnapshot",
        "protocolCompositionSnapshot",
        "protocolsSnapshot",
        "resilientClassesSnapshot",
        "resultBuilderDSLSnapshot",
        "sameTypeRequirementsSnapshot",
        "staticMembersSnapshot",
        "stringInterpolationSnapshot",
        "structsSnapshot",
        "subscriptsSnapshot",
        "tuplesSnapshot",
        "unsafePointersSnapshot",
        "vTableEntryVariantsSnapshot",
        "weakUnownedReferencesSnapshot",
    ]

    @Test func actorsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "Actors")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func associatedTypeWitnessPatternsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "AssociatedTypeWitnessPatterns")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func asyncSequenceSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "AsyncSequenceTests")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func attributesSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "Attributes")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func basicTypesSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "BasicTypes")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func builtinTypeFieldsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "BuiltinTypeFields")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func classBoundGenericsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "ClassBoundGenerics")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func classesSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "Classes")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func codableSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "CodableTests")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func collectionConformancesSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "CollectionConformances")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func concurrencySnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "Concurrency")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func conditionalConformanceVariantsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "ConditionalConformanceVariants")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func customLiteralsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "CustomLiterals")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func defaultImplementationVariantsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "DefaultImplementationVariants")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func deinitVariantsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "DeinitVariants")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func dependentTypeAccessSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "DependentTypeAccess")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func diamondInheritanceSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "DiamondInheritance")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func distributedActorsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "DistributedActors")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func enumsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "Enums")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func errorTypesSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "ErrorTypes")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func existentialAnySnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "ExistentialAny")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func extensionsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "Extensions")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func fieldDescriptorVariantsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "FieldDescriptorVariants")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func functionFeaturesSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "FunctionFeatures")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func functionTypesSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "FunctionTypes")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func genericFieldLayoutSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "GenericFieldLayout")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func genericRequirementVariantsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "GenericRequirementVariants")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func genericsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "Generics")
        assertSnapshot(of: output, as: .lines)
    }

    // GlobalDeclarations.swift contains only module-scope `let`/`var`/`func`
    // declarations, which emit no TypeContextDescriptor — the snapshot is
    // intentionally (near-)empty. Full-module coverage for globals comes from
    // the interface snapshot. See spec §"Edge-case categories".
    @Test func globalDeclarationsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "GlobalDeclarations")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func initializersSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "Initializers")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func keyPathsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "KeyPaths")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func markerProtocolsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "MarkerProtocols")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func metatypeUsageSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "MetatypeUsage")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func nestedFunctionsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "NestedFunctions")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func nestedGenericsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "NestedGenerics")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func neverExtensionsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "NeverExtensions")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func noncopyableSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "Noncopyable")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func objCClassWrappersSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "ObjCClassWrapperFixtures")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func objCResilientStubsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "ObjCResilientStubFixtures")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func opaqueReturnTypesSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "OpaqueReturnTypes")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func operatorsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "Operators")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func optionSetAndRawRepresentableSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "OptionSetAndRawRepresentable")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func overloadedMembersSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "OverloadedMembers")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func propertyWrapperVariantsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "PropertyWrapperVariants")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func protocolCompositionSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "ProtocolComposition")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func protocolsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "Protocols")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func resilientClassesSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "ResilientClassFixtures")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func resultBuilderDSLSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "ResultBuilderDSL")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func sameTypeRequirementsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "SameTypeRequirements")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func staticMembersSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "StaticMembers")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func stringInterpolationSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "StringInterpolations")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func structsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "Structs")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func subscriptsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "Subscripts")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func tuplesSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "Tuples")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func unsafePointersSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "UnsafePointers")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func vTableEntryVariantsSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "VTableEntryVariants")
        assertSnapshot(of: output, as: .lines)
    }

    @Test func weakUnownedReferencesSnapshot() async throws {
        let output = try await collectDump(for: machOFile, inNamespace: "WeakUnownedReferences")
        assertSnapshot(of: output, as: .lines)
    }
}
