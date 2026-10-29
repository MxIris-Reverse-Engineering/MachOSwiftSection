import Foundation
import Testing
import MachOKit
import MachOFoundation
@_spi(Internals) import Demangling
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@_spi(Internals) @testable import SwiftInspection

/// `ObjCProtocolRequirementBuilder` (evolution proposal
/// `swift-declared-objc-protocols`): the requirements of an `@objc` protocol
/// declared in Swift, built from its Objective-C record as Swift declarations
/// — every list, in record order, a property and a subscript where their
/// getters are — through both readers.
@Suite(.serialized, ExclusiveImageAccess(SwiftDeclaredObjCProtocolsFixture.moduleName))
struct ObjCProtocolRequirementBuilderTests {
    private static let moduleName = SwiftDeclaredObjCProtocolsFixture.moduleName

    private static func requirements(of name: String, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [ObjCProtocolRequirement] {
        let declared = try #require(SwiftDeclaredObjCProtocolIndex.shared.protocols(in: machO).first { $0.qualifiedName == "\(moduleName).\(name)" })
        let record = try #require(declared.record)
        let protocolNode = try #require(try demangleAsNodeTransient(declared.mangledName).first(of: .protocol))
        return ObjCProtocolRequirementBuilder.requirements(of: record, protocolNode: protocolNode, in: machO)
    }

    private static func printed(_ requirement: ObjCProtocolRequirement) -> String {
        requirement.node.print(using: .interface)
    }

    private static func expectDerivedSelectors(in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        let requirements = try requirements(of: "DerivedSelectors", in: machO)
        #expect(requirements.map(\.selector) == [
            "initWithIdentifier:", "nameFor:", "teamNameFor:error:", "hangPointsWithInput:error:", "perform:with:",
            "downloadWithIdentifier:completion:", "tokenAndReturnError:", "reload", "title", "isEnabled",
            "objectAtIndexedSubscript:", "makeDefault", "shared", "scrollTo:animated:", "optionalCount",
        ])
        #expect(requirements.map(\.kind) == [
            .initializer, .method, .method, .method, .method, .method, .method, .method, .property, .property,
            .subscript, .method, .property, .method, .property,
        ])

        let bySelector = Dictionary(requirements.map { ($0.selector, $0) }, uniquingKeysWith: { first, _ in first })
        // Accessors: a read-only property, a settable one, a settable subscript.
        #expect(bySelector["title"]?.isSettable == false)
        #expect(bySelector["isEnabled"]?.setterSelector == "setIsEnabled:")
        #expect(bySelector["objectAtIndexedSubscript:"]?.setterSelector == "setObject:atIndexedSubscript:")
        // Class members and optional requirements.
        #expect(bySelector["makeDefault"]?.isClassMember == true)
        #expect(bySelector["shared"]?.isClassMember == true)
        #expect(bySelector["initWithIdentifier:"]?.isClassMember == false)
        #expect(requirements.filter(\.isOptional).map(\.selector) == ["scrollTo:animated:", "optionalCount"])

        // The declarations: the importer's names with the `With` Swift
        // inserted undone, bridged types, `!` where nullability is unknown,
        // `?` inside a closure, `throws` from the error convention.
        let expectedFragments: [String: String] = [
            "nameFor:": "name(for: Any!) -> Swift.String!",
            "teamNameFor:error:": "teamName(for: Swift.String!) throws -> Swift.String",
            "hangPointsWithInput:error:": "hangPoints(input: NSObject!) throws -> [Any]",
            "perform:with:": "perform(_: Swift.String!, with: Any!)",
            "downloadWithIdentifier:completion:": "download(identifier: Swift.String!, completion: ((Foundation.URL?, Swift.Error?) -> ())!)",
            "tokenAndReturnError:": "token() throws -> Swift.String",
            "scrollTo:animated:": "scroll(to: Swift.Int, animated: Swift.Bool)",
            "makeDefault": "makeDefault() -> NSObject!",
            "initWithIdentifier:": "init(identifier: Swift.String!)",
            "title": "title",
        ]
        for (selector, fragment) in expectedFragments {
            let requirement = try #require(bySelector[selector], "\(selector)")
            #expect(printed(requirement).contains(fragment), "\(selector): \(printed(requirement))")
        }
        #expect(printed(try #require(bySelector["title"])).contains("Swift.String!"))
        #expect(printed(try #require(bySelector["shared"])).hasPrefix("static "))
    }

    @Test func derivedSelectorsFromTheFile() throws {
        try Self.expectDerivedSelectors(in: SwiftDeclaredObjCProtocolsFixture.machOFile(.full))
    }

    @Test func derivedSelectorsFromTheLoadedImage() throws {
        try Self.expectDerivedSelectors(in: SwiftDeclaredObjCProtocolsFixture.loadedImage())
    }

    /// A requirement typed with another of the image's protocols, renamed to
    /// its own name, and an explicit selector Apple's way.
    @Test func protocolTypesAndExplicitSelectors() throws {
        let machO = try SwiftDeclaredObjCProtocolsFixture.machOFile(.full)
        let refined = try Self.requirements(of: "RefinedProtocol", in: machO)
        #expect(refined.map(\.selector) == ["refine"])
        #expect(Self.printed(refined[0]).contains("refine()"))

        let sameNameRenamed = try Self.requirements(of: "SameNameRenamed", in: machO)
        #expect(sameNameRenamed.map(\.selector) == ["ping"])
    }
}
