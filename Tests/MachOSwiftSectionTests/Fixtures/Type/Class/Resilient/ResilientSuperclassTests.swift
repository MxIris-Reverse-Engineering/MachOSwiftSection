import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ResilientSuperclass`.
///
/// `ResilientSuperclass` is the trailing-object record carrying a
/// `RelativeDirectRawPointer` to the superclass when a class has
/// `hasResilientSuperclass == true`. The suite drives the new
/// `ResilientClassFixtures.ResilientChild` (whose parent
/// `SymbolTestsHelper.ResilientBase` is in a different module, so the
/// child's class context descriptor carries the trailing record) and
/// asserts cross-reader agreement on the discovered scalar offset.
@Suite
final class ResilientSuperclassTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ResilientSuperclass"
    static var registeredTestMethodNames: Set<String> {
        ResilientSuperclassBaseline.registeredTestMethodNames
    }

    /// Helper: load the `ResilientSuperclass` record from
    /// `ResilientClassFixtures.ResilientChild` (whose parent
    /// `SymbolTestsHelper.ResilientBase` is cross-module — only that
    /// triggers `hasResilientSuperclass`).
    private func loadResilientChildSuperclass(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ResilientSuperclass {
        let descriptor = try BaselineFixturePicker.class_ResilientChild(in: machO)
        let classWrapper = try Class(descriptor: descriptor, in: machO)
        return try required(classWrapper.resilientSuperclass)
    }

    @Test func offset() async throws {
        let fileSubject = try loadResilientChildSuperclass(in: machOFile)
        let imageSubject = try loadResilientChildSuperclass(in: machOImage)
        let result = try acrossAllReaders(
            file: { fileSubject.offset },
            image: { imageSubject.offset }
        )
        #expect(result == ResilientSuperclassBaseline.resilientChild.offset)
    }

    @Test func layout() async throws {
        let fileSubject = try loadResilientChildSuperclass(in: machOFile)
        let imageSubject = try loadResilientChildSuperclass(in: machOImage)
        // The relative raw pointer's relativeOffset scalar must agree
        // across readers (it's a stable file/image-relative displacement).
        let result = try acrossAllReaders(
            file: { fileSubject.layout.superclass.relativeOffset },
            image: { imageSubject.layout.superclass.relativeOffset }
        )
        #expect(result == ResilientSuperclassBaseline.resilientChild.layoutSuperclassRelativeOffset)
    }
}
