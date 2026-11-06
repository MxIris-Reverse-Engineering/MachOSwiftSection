import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Pins what a layout lookup builds (evolution proposal
/// `machofile-performance`): a lookup folds images into the indexes of its
/// own kind only, an image builds an index the first time it is read, and
/// every universe that folds an image in shares one reference to it.
///
/// Before, folding a dependency built all seven of its indexes, so the type
/// lookups that resolve field types also read every passed dependency's
/// Objective-C protocol list — 2.4 of the 12 seconds the dependency indexes
/// of SwiftUI cost — and each universe built its own copy of an image's
/// indexes.
@Suite
final class ImageUniverseLazyFoldingTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    /// A type defined nowhere folds every image into the type index and
    /// nothing into the others.
    @Test func typeLookupsFoldOnlyTheTypeIndexes() throws {
        let universe = try ImageUniverse.dependencyClosure(root: machOFile, searchPaths: [.systemDyldSharedCache])
        try #require(universe.dependencyImageCount > 0, "the closure must collect dependency images")

        #expect(universe.resolveType(byQualifiedTypeName: "NoSuchModule.NoSuchType") == nil)

        #expect(universe.foldedImageCount(for: .types) == universe.dependencyImageCount + 1)
        #expect(universe.foldedImageCount(for: .protocols) == 0)
        #expect(universe.foldedImageCount(for: .objCClasses) == 0)
        #expect(universe.foldedImageCount(for: .associatedTypeWitnesses) == 0)
    }

    /// Reading one index builds that index alone. Asked of a reference of
    /// its own, so no other test's lookups can have built anything on it.
    @Test func readingAnIndexBuildsOnlyThatIndex() throws {
        let reference = ImageReference(indexingLazily: machOFile)
        #expect(reference.builtIndexNamesForTesting.isEmpty)

        #expect(!reference.typeDescriptorsByQualifiedName.isEmpty)
        #expect(reference.builtIndexNamesForTesting == ["typeDescriptors"])

        _ = reference.protocolClassConstraintsByQualifiedName
        #expect(reference.builtIndexNamesForTesting == ["typeDescriptors", "protocolClassConstraints"])
    }

    /// Two universes over one root share the root's reference and the
    /// reference of every dependency both fold in.
    @Test func universesShareEachImagesReference() throws {
        let firstUniverse = try ImageUniverse.dependencyClosure(root: machOFile, searchPaths: [.systemDyldSharedCache])
        let secondUniverse = try ImageUniverse.dependencyClosure(root: machOFile, searchPaths: [.systemDyldSharedCache])
        #expect(firstUniverse.rootImage === secondUniverse.rootImage)

        let firstResolution = try #require(firstUniverse.resolveType(byQualifiedTypeName: "Swift.Int"))
        let secondResolution = try #require(secondUniverse.resolveType(byQualifiedTypeName: "Swift.Int"))
        #expect(firstResolution.image === secondResolution.image)
        #expect(firstResolution.image !== firstUniverse.rootImage)
    }
}
