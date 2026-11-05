import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
@testable import MachOTestingSupport

/// Existentials of `@objc` protocols declared in Swift that only their field
/// descriptors name (evolution proposal `swift-declared-objc-protocols`):
/// one the source renamed with `@objc(Name)` has a record under that name,
/// and one declared in a type a `_TtPC…` name — neither of which the legacy
/// `_TtP<module><name>_` reading recognizes, so the existential's layout went
/// unresolved. The runtime field-offset vector of the non-generic holder is
/// the ground truth, on the in-process reader and the file reader alike.
@Suite(.serialized, ExclusiveImageAccess(SwiftDeclaredObjCProtocolsFixture.moduleName))
struct SwiftDeclaredObjCProtocolExistentialLayoutTests {
    private static let qualifiedTypeName = "\(SwiftDeclaredObjCProtocolsFixture.moduleName).RenamedProtocolExistentialHolder"

    @Test func renamedAndNestedProtocolExistentialsResolve() throws {
        let machOImage = try SwiftDeclaredObjCProtocolsFixture.loadedImage()
        let runtimeOffsets = try #require(try runtimeFieldOffsets(ofQualifiedTypeName: Self.qualifiedTypeName, in: machOImage), "no runtime field-offset vector")

        let imageAggregate = try fieldLayout(ofQualifiedTypeName: Self.qualifiedTypeName, with: StaticLayoutCalculator(machO: machOImage), in: machOImage)
        assertFullyComputed(imageAggregate, equals: runtimeOffsets, typeName: Self.qualifiedTypeName)

        let machOFile = try SwiftDeclaredObjCProtocolsFixture.machOFile(.full)
        let fileAggregate = try fieldLayout(ofQualifiedTypeName: Self.qualifiedTypeName, with: StaticLayoutCalculator(machO: machOFile), in: machOFile)
        assertFullyComputed(fileAggregate, equals: runtimeOffsets, typeName: "\(Self.qualifiedTypeName) (MachOFile)")
    }

    /// Over a whole dependency closure, a protocol the root's own Objective-C
    /// protocol records name resolves in the root. Asked of the Swift
    /// protocol descriptors first, every such protocol — which has none —
    /// indexed the root's entire closure before its record was looked at:
    /// hundreds of images of the system's dyld cache for each image a host
    /// read, which is how RuntimeViewer's offline service, laying out a
    /// field of a Swift-declared `@objc` protocol in DockHelper, mapped the
    /// cache files over two thousand times.
    @Test func objCProtocolExistentialsResolveWithoutIndexingDependencies() throws {
        let machOImage = try SwiftDeclaredObjCProtocolsFixture.loadedImage()
        let runtimeOffsets = try #require(try runtimeFieldOffsets(ofQualifiedTypeName: Self.qualifiedTypeName, in: machOImage), "no runtime field-offset vector")

        let machOFile = try SwiftDeclaredObjCProtocolsFixture.machOFile(.full)
        let universe = try ImageUniverse.dependencyClosure(root: machOFile, searchPaths: SwiftDeclaredObjCProtocolsFixture.dependencySearchPaths())
        try #require(universe.dependencyImageCount > 0, "the closure must collect dependency images")
        let fileAggregate = try fieldLayout(ofQualifiedTypeName: Self.qualifiedTypeName, with: StaticLayoutCalculator(imageUniverse: universe), in: machOFile)

        assertFullyComputed(fileAggregate, equals: runtimeOffsets, typeName: "\(Self.qualifiedTypeName) (MachOFile, dependency closure)")
        #expect(universe.indexedDependencyImageCount == 0, "indexed \(universe.indexedDependencyImageCount) of \(universe.dependencyImageCount) dependency images")
    }

    /// The protocols the image declares, as the layout engine keys them.
    @Test func imageIndexNamesRenamedAndNestedProtocols() throws {
        let qualifiedNames = ObjCProtocolIndex.qualifiedNames(in: try SwiftDeclaredObjCProtocolsFixture.machOFile(.full))
        let moduleName = SwiftDeclaredObjCProtocolsFixture.moduleName
        #expect(qualifiedNames.contains("\(moduleName).SameNameRenamed"))
        #expect(qualifiedNames.contains("\(moduleName).Outer.NestedProtocol"))
        // The legacy reading still covers the kit's records the client
        // holds copies of.
        #expect(qualifiedNames.contains("\(SwiftDeclaredObjCProtocolsFixture.kitModuleName).KitObserver"))
    }
}
