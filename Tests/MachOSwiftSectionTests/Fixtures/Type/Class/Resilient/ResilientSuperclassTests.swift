import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ResilientSuperclass`.
///
/// `ResilientSuperclass` is the trailing-object record carrying a
/// `RelativeDirectRawPointer` to the superclass when a class has
/// `hasResilientSuperclass == true`. The fixture's
/// `Classes.ExternalSwiftSubclassTest` (inherited from
/// SymbolTestsHelper.Object) surfaces this record. We assert
/// cross-reader agreement on the discovered offset.
@Suite
final class ResilientSuperclassTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ResilientSuperclass"
    static var registeredTestMethodNames: Set<String> {
        ResilientSuperclassBaseline.registeredTestMethodNames
    }

    /// Helper: find the first class in the fixture with a resilient
    /// superclass and return its `ResilientSuperclass` record.
    private func loadFirstResilientSuperclass(in machO: some MachOSwiftSectionRepresentableWithCache)
        throws -> ResilientSuperclass?
    {
        for descriptor in try machO.swift.typeContextDescriptors.compactMap(\.class)
            where descriptor.hasResilientSuperclass
        {
            let classWrapper = try Class(descriptor: descriptor, in: machO)
            if let resilient = classWrapper.resilientSuperclass {
                return resilient
            }
        }
        return nil
    }

    @Test func offset() async throws {
        guard
            let fileSubject = try loadFirstResilientSuperclass(in: machOFile),
            let imageSubject = try loadFirstResilientSuperclass(in: machOImage)
        else {
            // No resilient-superclass class in fixture; skip.
            return
        }
        #expect(fileSubject.offset == imageSubject.offset)
        #expect(fileSubject.offset == ResilientSuperclassBaseline.firstResilientSuperclass.offset)
    }

    @Test func layout() async throws {
        guard
            let fileSubject = try loadFirstResilientSuperclass(in: machOFile),
            let imageSubject = try loadFirstResilientSuperclass(in: machOImage)
        else {
            return
        }
        // The relative raw pointer's relativeOffset scalar must agree
        // across readers (it's a stable file/image-relative displacement).
        #expect(fileSubject.layout.superclass.relativeOffset == imageSubject.layout.superclass.relativeOffset)
    }
}
