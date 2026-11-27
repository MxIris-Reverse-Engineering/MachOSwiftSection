import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Internals) import SwiftObjCInterop
@testable import SwiftSectionTestingSupport

/// An image no Swift code went into has no extension of Swift's, so none of
/// its categories gives a conformance extension — OS X 10.9's AppKit, all
/// Objective-C, printed four. An image Swift went into keeps its categories,
/// Objective-C code's among them: the linker merges the categories of one
/// class, so the Swift extensions' protocols and the Objective-C category's
/// arrive in one list.
///
/// Holds `ExclusiveImageAccess` because the adoption index is per-image
/// state the indexer and the queries below share.
@Suite(.serialized, ExclusiveImageAccess(ObjCWrittenCategoriesFixture.moduleName))
struct ObjCWrittenCategoryConformanceTests {
    private static let moduleName = ObjCWrittenCategoriesFixture.moduleName

    private static func indexer<MachO: MachOSwiftSectionRepresentableWithCache>(for machO: MachO) async throws -> SwiftDeclarationIndexer<MachO> {
        let indexer = SwiftDeclarationIndexer(configuration: SwiftDeclarationIndexConfiguration(), in: machO)
        try await indexer.prepare()
        return indexer
    }

    private static func expectNoCategoryConformances(in machO: some MachOSwiftSectionRepresentableWithCache) async throws {
        #expect(ObjCProtocolAdoptionIndex.shared.categoryAdoptions(in: machO).map(\.classRuntimeName) == [])
        let indexer = try await Self.indexer(for: machO)
        #expect(indexer.objcCategoryConformances.map(\.extendedTypeName.name) == [])
    }

    @Test func objectiveCOnlyImageFromTheFile() async throws {
        try await Self.expectNoCategoryConformances(in: ObjCWrittenCategoriesFixture.machOFile(.objectiveCOnly))
    }

    @Test func objectiveCOnlyImageFromTheLoadedImage() async throws {
        try await Self.expectNoCategoryConformances(in: ObjCWrittenCategoriesFixture.loadedImage(.objectiveCOnly))
    }

    /// The two extensions of `DateFormatter` adopt one protocol each; both
    /// reach the conformance extension of `NSDateFormatter`.
    private static func expectSwiftProtocolsKept(in machO: some MachOSwiftSectionRepresentableWithCache) async throws {
        let indexer = try await Self.indexer(for: machO)
        let dateFormatterProtocolNames = indexer.objcCategoryConformances
            .filter { $0.extendedTypeName.name == "__C.NSDateFormatter" }
            .flatMap { $0.protocolNames.map(\.name) }
        #expect(Set(dateFormatterProtocolNames).isSuperset(of: ["\(moduleName).SwiftDeclaredAdoption", "\(moduleName).SecondSwiftDeclaredAdoption"]))
    }

    @Test func mixedImageFromTheFile() async throws {
        try await Self.expectSwiftProtocolsKept(in: ObjCWrittenCategoriesFixture.machOFile(.mixed))
    }

    @Test func mixedImageFromTheLoadedImage() async throws {
        try await Self.expectSwiftProtocolsKept(in: ObjCWrittenCategoriesFixture.loadedImage(.mixed))
    }
}
