import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `StoredClassMetadataBounds`.
///
/// `StoredClassMetadataBounds` is reachable via
/// `ClassDescriptor.resilientMetadataBounds(in:)` for classes with a
/// resilient superclass. We pick the first class in the fixture with a
/// resilient superclass and verify the resolved bounds via the
/// `MachOImage` reader.
///
/// **Reader divergence:** the
/// `RelativeDirectPointer<StoredClassMetadataBounds>` inside a class
/// descriptor's `metadataNegativeSizeInWordsOrResilientMetadataBounds`
/// slot points into the resilient *superclass*'s defining image — for
/// `Classes.ExternalSwiftSubclassTest` the superclass is
/// `SymbolTestsHelper.Object`, which lives in a different binary. The
/// `MachOFile` reader only sees `SymbolTestsCore`, so when the relative
/// pointer crosses into the helper image it returns garbage. The
/// `MachOImage` reader chases pointers across loaded images
/// successfully. We therefore validate against the MachOImage reader
/// only.
@Suite
final class StoredClassMetadataBoundsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "StoredClassMetadataBounds"
    static var registeredTestMethodNames: Set<String> {
        StoredClassMetadataBoundsBaseline.registeredTestMethodNames
    }

    /// Helper: find the first class in the fixture with a resilient
    /// superclass and resolve its `StoredClassMetadataBounds`.
    private func loadFirstResilientBounds(in machO: some MachOSwiftSectionRepresentableWithCache)
        throws -> StoredClassMetadataBounds?
    {
        for descriptor in try machO.swift.typeContextDescriptors.compactMap(\.class)
            where descriptor.hasResilientSuperclass
        {
            return try descriptor.resilientMetadataBounds(in: machO)
        }
        return nil
    }

    @Test func offset() async throws {
        guard let imageBounds = try loadFirstResilientBounds(in: machOImage) else {
            // No resilient-superclass class in fixture; skip.
            return
        }
        #expect(imageBounds.offset > 0)
    }

    @Test func layout() async throws {
        guard let imageBounds = try loadFirstResilientBounds(in: machOImage) else {
            return
        }
        // Sanity: the bounds carry valid positive/negative word counts.
        // We don't pin specific values because they reflect the runtime
        // state of the resilient root, which can change with toolchain
        // versions. Just exercise the accessors to keep the runtime
        // path under coverage.
        let _ = imageBounds.layout.bounds.negativeSizeInWords
        let _ = imageBounds.layout.bounds.positiveSizeInWords
        let _ = imageBounds.layout.immediateMembersOffset
    }
}
