import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport
import Demangling

/// Validates the three resolution paths added on top of the generic-instantiation
/// engine: nested types of a *specialized* generic parent (parent-chain-preserving
/// name resolution), associated-type fields resolved through `__swift5_assocty`
/// witnesses, and constrained ("extended") existentials. Every holder is
/// non-generic, so its runtime field-offset vector is the ground truth. Verified
/// on the in-process reader and the offline `MachOFile` reader.
@Suite
final class AssociatedTypeAndConstrainedExistentialLayoutTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    private static let fullyResolvingHolders = [
        "NestedInSpecializedParentFieldHolder",
        "AssociatedTypeFieldHolder",
        "ConstrainedExistentialFieldHolder",
    ]

    @MainActor
    @Test func holdersFullyResolveAndMatchRuntime() async throws {
        let machO = machOImage
        // These holders reference stdlib conformances (Array: Collection) and
        // stdlib types, so the dependency closure over the shared cache is
        // needed to resolve the associated-type witnesses and existential
        // protocol constraints. Build closures for both readers.
        let imageUniverse = try ImageUniverse.dependencyClosure(root: machO)
        let calculator = StaticLayoutCalculator(imageUniverse: imageUniverse)
        let fileUniverse = try ImageUniverse.dependencyClosure(root: machOFile, searchPaths: [.systemDyldSharedCache])
        let fileCalculator = StaticLayoutCalculator(imageUniverse: fileUniverse)

        for shortName in Self.fullyResolvingHolders {
            let qualifiedTypeName = "SymbolTestsCore.GenericFieldLayout.\(shortName)"
            let runtimeOffsets = try #require(
                try runtimeFieldOffsets(ofQualifiedTypeName: qualifiedTypeName, in: machO),
                "no runtime field-offset vector for \(qualifiedTypeName)"
            )
            let aggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: calculator, in: machO)
            assertFullyComputed(aggregate, equals: runtimeOffsets, typeName: qualifiedTypeName)

            let fileAggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: fileCalculator, in: machOFile)
            assertFullyComputed(fileAggregate, equals: runtimeOffsets, typeName: "\(qualifiedTypeName) (MachOFile)")
        }
    }
}
