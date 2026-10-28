import Foundation
import Testing
import MachOKit
import MachOFoundation
@_spi(Internals) import Demangling
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@_spi(Internals) @testable import SwiftInspection

/// `SwiftDeclaredObjCProtocolIndex` (evolution proposal
/// `swift-declared-objc-protocols`): which `@objc` protocols declared in
/// Swift an image defines — from `__swift5_fieldmd`, never from the records'
/// `IsSwift` bit, which the kit's protocols carry in the client too — each
/// paired with its Objective-C record, read in full through every reader.
@Suite(.serialized, ExclusiveImageAccess(SwiftDeclaredObjCProtocolsFixture.moduleName))
struct SwiftDeclaredObjCProtocolIndexTests {
    private static let moduleName = SwiftDeclaredObjCProtocolsFixture.moduleName

    private static let kitModuleName = SwiftDeclaredObjCProtocolsFixture.kitModuleName

    private static func defaultRuntimeName(of name: String, module: String = moduleName) -> String {
        "_TtP\(module.count)\(module)\(name.count)\(name)_"
    }

    private static func qualifiedName(_ name: String) -> String {
        "\(moduleName).\(name)"
    }

    private static func protocolsByQualifiedName(in machO: some MachORepresentableWithCache) -> [String: SwiftDeclaredObjCProtocol] {
        Dictionary(SwiftDeclaredObjCProtocolIndex.shared.protocols(in: machO).map { ($0.qualifiedName, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The client's five protocols and nothing else — not the kit's, whose
    /// Swift-emitted copies the client holds — paired by default runtime name
    /// or, renamed to its own name, by name; renamed to another, unpaired.
    private static func expectDeclaredProtocols(in machO: some MachORepresentableWithCache) throws {
        let protocols = protocolsByQualifiedName(in: machO)
        #expect(Set(protocols.keys) == Set(["DerivedSelectors", "SameNameRenamed", "DifferentlyNamed", "RefinedProtocol", "InternalProtocol", "Outer.NestedProtocol"].map(qualifiedName)))
        for declaredProtocol in protocols.values {
            guard case .fieldDescriptor = declaredProtocol.evidence else {
                Issue.record("\(declaredProtocol.qualifiedName) was not found through its field descriptor")
                continue
            }
            #expect(declaredProtocol.mangledName.hasPrefix("$s"), "\(declaredProtocol.qualifiedName)")
        }

        let derivedSelectors = try #require(protocols[qualifiedName("DerivedSelectors")])
        #expect(derivedSelectors.record?.runtimeName == defaultRuntimeName(of: "DerivedSelectors"))
        #expect(!derivedSelectors.hasExplicitObjCName)

        let refinedProtocol = try #require(protocols[qualifiedName("RefinedProtocol")])
        #expect(refinedProtocol.record?.runtimeName == defaultRuntimeName(of: "RefinedProtocol"))
        #expect(refinedProtocol.record?.inheritedProtocolRuntimeNames == ["SameNameRenamed"])

        let internalProtocol = try #require(protocols[qualifiedName("InternalProtocol")])
        #expect(internalProtocol.record?.runtimeName == defaultRuntimeName(of: "InternalProtocol"))

        let sameNameRenamed = try #require(protocols[qualifiedName("SameNameRenamed")])
        #expect(sameNameRenamed.record?.runtimeName == "SameNameRenamed")
        #expect(sameNameRenamed.hasExplicitObjCName)

        let differentlyNamed = try #require(protocols[qualifiedName("DifferentlyNamed")])
        #expect(differentlyNamed.record == nil)
        #expect(differentlyNamed.hasExplicitObjCName)

        // The renamed records nothing claims: the client's own one renamed to
        // another name, and the kit's renamed one it references.
        let unclaimedNames = SwiftDeclaredObjCProtocolIndex.shared.unclaimedSwiftEmittedRecords(in: machO).map(\.runtimeName)
        #expect(Set(unclaimedNames) == ["PRBDifferentlyNamed", "KITRenamedObserver"])

        #expect(SwiftDeclaredObjCProtocolIndex.shared.qualifiedName(forRuntimeName: defaultRuntimeName(of: "DerivedSelectors"), in: machO) == qualifiedName("DerivedSelectors"))
        #expect(SwiftDeclaredObjCProtocolIndex.shared.qualifiedName(forRuntimeName: "SameNameRenamed", in: machO) == qualifiedName("SameNameRenamed"))
        #expect(SwiftDeclaredObjCProtocolIndex.shared.qualifiedName(forRuntimeName: defaultRuntimeName(of: "KitObserver", module: kitModuleName), in: machO) == nil)

        try expectDerivedSelectorsRecord(try #require(derivedSelectors.record))
    }

    /// Every list of the record, and one extended encoding per method in
    /// list order: the array MachOObjCSection reads only the first entry of.
    private static func expectDerivedSelectorsRecord(_ record: ObjCProtocolRecord) throws {
        #expect(record.isEmittedBySwift)
        #expect(record.inheritedProtocolRuntimeNames == ["NSObject"])
        #expect(Set(record.requiredInstanceMethods.map(\.selector)) == [
            "initWithIdentifier:", "nameFor:", "teamNameFor:error:", "hangPointsWithInput:error:", "perform:with:",
            "downloadWithIdentifier:completion:", "tokenAndReturnError:", "reload", "title", "isEnabled", "setIsEnabled:",
            "objectAtIndexedSubscript:", "setObject:atIndexedSubscript:",
        ])
        #expect(Set(record.requiredClassMethods.map(\.selector)) == ["makeDefault", "shared"])
        #expect(Set(record.optionalInstanceMethods.map(\.selector)) == ["scrollTo:animated:", "optionalCount"])
        #expect(record.optionalClassMethods.isEmpty)
        #expect(record.instanceProperties.map(\.name) == ["title", "isEnabled", "optionalCount"])
        #expect(record.instanceProperties.first?.attributes == #"T@"NSString",N,R"#)
        #expect(record.classProperties.map(\.name) == ["shared"])

        let extendedEncodingsBySelector = Dictionary(record.allMethods.map { ($0.selector, $0.extendedTypeEncoding) }, uniquingKeysWith: { first, _ in first })
        #expect(record.allMethods.allSatisfy { $0.extendedTypeEncoding != nil })
        #expect(extendedEncodingsBySelector["teamNameFor:error:"] == #"@"NSString"32@0:8@"NSString"16^@24"#)
        #expect(extendedEncodingsBySelector["downloadWithIdentifier:completion:"] == #"v32@0:8@"NSString"16@?<v@?@"NSURL"@"NSError">24"#)
        #expect(extendedEncodingsBySelector["scrollTo:animated:"] == "v28@0:8q16B24")
        #expect(extendedEncodingsBySelector["shared"] == #"@"NSObject"16@0:8"#)
        // The plain encoding stays the method list's own.
        #expect(record.requiredInstanceMethods.first { $0.selector == "teamNameFor:error:" }?.typeEncoding == "@32@0:8@16^@24")
    }

    @Test func fileDefinesItsOwnProtocolsOnly() throws {
        try Self.expectDeclaredProtocols(in: SwiftDeclaredObjCProtocolsFixture.machOFile(.full))
    }

    /// Nothing the index reads is a local symbol.
    @Test func strippedFileDefinesTheSameProtocols() throws {
        try Self.expectDeclaredProtocols(in: SwiftDeclaredObjCProtocolsFixture.machOFile(.strippedLocals))
    }

    @Test func loadedImageDefinesTheSameProtocols() throws {
        try Self.expectDeclaredProtocols(in: SwiftDeclaredObjCProtocolsFixture.loadedImage())
    }

    /// No `__swift5_fieldmd`: a `_TtP` record spelling the image's own module
    /// is the image's; the renamed ones go unseen, and the kit's copies stay
    /// out.
    @Test func withoutReflectionMetadataTheRuntimeNamesDecide() throws {
        let machO = try SwiftDeclaredObjCProtocolsFixture.machOFile(.withoutReflectionMetadata)
        #expect(throws: (any Error).self) { try machO.swift.fieldDescriptors }

        let protocols = Self.protocolsByQualifiedName(in: machO)
        #expect(Set(protocols.keys) == Set(["DerivedSelectors", "RefinedProtocol", "InternalProtocol", "Outer.NestedProtocol"].map(Self.qualifiedName)))
        for declaredProtocol in protocols.values {
            #expect(declaredProtocol.evidence == .runtimeName, "\(declaredProtocol.qualifiedName)")
            #expect(!declaredProtocol.hasExplicitObjCName, "\(declaredProtocol.qualifiedName)")
            // The modern spelling of the name, as a field descriptor gives it.
            let node = try demangleAsNodeTransient(declaredProtocol.mangledName)
            #expect(NodeTypeNaming.protocolQualifiedName(of: try #require(node.first(of: .protocol))) == declaredProtocol.qualifiedName)
        }
        try Self.expectDerivedSelectorsRecord(try #require(protocols[Self.qualifiedName("DerivedSelectors")]?.record))
    }

    /// The field descriptors the index reads are the section walk's: one of
    /// kind `ObjCProtocol` per protocol the client declares.
    @Test func fieldDescriptorWalkFindsTheProtocolRecords() throws {
        let machO = try SwiftDeclaredObjCProtocolsFixture.machOFile(.full)
        let descriptors = try machO.swift.fieldDescriptors
        for (earlier, later) in zip(descriptors, descriptors.dropFirst()) {
            #expect(later.offset - earlier.offset == earlier.actualSize)
        }
        #expect(descriptors.filter { $0.kind == .objCProtocol }.count == 6)
    }
}
