import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Internals) import SwiftObjCInterop
@testable import SwiftSectionTestingSupport

/// A category is an extension of Swift's only when the Swift compiler
/// emitted it — named after one of the image's Swift modules — so the
/// categories Objective-C code declares give no conformance extension: not
/// in an image of Objective-C code alone (OS X 10.9's AppKit printed four),
/// and not beside a Swift module's own categories in one image.
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

    @Test func objectiveCOnlyImageHasNoCategoryConformances() async throws {
        let machO = try ObjCWrittenCategoriesFixture.machOFile(.objectiveCOnly)
        #expect(ObjCProtocolAdoptionIndex.shared.categoryAdoptions(in: machO).map(\.classRuntimeName) == [])
        let indexer = try await Self.indexer(for: machO)
        #expect(indexer.objcCategoryConformances.map(\.extendedTypeName.name) == [])
    }

    /// The two extensions of `DateFormatter`, named `ObjCWrittenCategoriesFixture`
    /// and `ObjCWrittenCategoriesFixture1`; the Objective-C categories on
    /// `NSString` and `NSDateFormatter` give nothing.
    private static func expectSwiftCategoriesOnly(in machO: some MachOSwiftSectionRepresentableWithCache) async throws {
        #expect(ObjCProtocolAdoptionIndex.shared.categoryAdoptions(in: machO).map(\.classRuntimeName) == ["NSDateFormatter", "NSDateFormatter"])
        let indexer = try await Self.indexer(for: machO)
        #expect(indexer.objcCategoryConformances.map(\.extendedTypeName.name) == ["__C.NSDateFormatter", "__C.NSDateFormatter"])
        #expect(indexer.objcCategoryConformances.map { $0.protocolNames.map(\.name) } == [["\(moduleName).SwiftDeclaredAdoption"], ["\(moduleName).SecondSwiftDeclaredAdoption"]])
    }

    @Test func mixedImageFromTheFile() async throws {
        try await Self.expectSwiftCategoriesOnly(in: ObjCWrittenCategoriesFixture.machOFile(.mixed))
    }

    @Test func mixedImageFromTheLoadedImage() async throws {
        try await Self.expectSwiftCategoriesOnly(in: ObjCWrittenCategoriesFixture.loadedImage())
    }
}
