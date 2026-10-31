import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDeclaration
import SwiftDeclarationRendering
import SwiftInterface
import Semantic
@testable import MachOTestingSupport

/// The `@objc` protocols a Swift module declares, on the interface path
/// (evolution proposal `swift-declared-objc-protocols`): they have no
/// protocol descriptor, and used to be missing from the interface — only
/// their protocol extensions printed, as extensions of nothing declared.
///
/// Holds `ExclusiveImageAccess` because the indexer registers an ancestor
/// resolver per image for the file leg.
@Suite(.serialized, ExclusiveImageAccess(SwiftDeclaredObjCProtocolsFixture.moduleName))
struct SwiftDeclaredObjCProtocolInterfaceTests {
    private static let moduleName = SwiftDeclaredObjCProtocolsFixture.moduleName

    private func interface(of machO: some MachOFieldLayoutRenderable) async throws -> String {
        try await printInterface(of: machO, marksCommentStructure: false).string
    }

    private func printInterface(of machO: some MachOFieldLayoutRenderable, marksCommentStructure: Bool) async throws -> SemanticString {
        var configuration = SwiftInterfaceBuilderConfiguration()
        configuration.indexConfiguration.dependencySearchPaths = try SwiftDeclaredObjCProtocolsFixture.dependencySearchPaths()
        configuration.printConfiguration.marksCommentStructure = marksCommentStructure
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: machO)
        try await builder.prepare()
        return try await builder.printRoot()
    }

    /// The notes of an `@objc` protocol — its requirements' Swift names, a
    /// requirement taken from a conformer — are marked like every other
    /// comment (evolution proposal `comment-structure`).
    @Test(arguments: SwiftDeclaredObjCProtocolsFixture.Variant.allCases)
    func markingCommentStructureKeepsTheContract(variant: SwiftDeclaredObjCProtocolsFixture.Variant) async throws {
        let machOFile = try SwiftDeclaredObjCProtocolsFixture.machOFile(variant)
        let marked = try await printInterface(of: machOFile, marksCommentStructure: true).frozen()
        let plain = try await printInterface(of: machOFile, marksCommentStructure: false).frozen()
        let violation = CommentStructureContract.violation(marked: marked, unmarked: plain)
        #expect(violation == nil, "\(violation ?? "")")
    }

    /// The block whose header line STARTS with `prefix`, through its closing
    /// brace at the same indentation.
    private func block(startingWith prefix: String, in interface: String) -> String? {
        let lines = interface.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.hasPrefix(prefix) }) else { return nil }
        let indentation = lines[start].prefix { $0 == " " }
        guard let end = lines[start...].firstIndex(where: { $0 == "\(indentation)}" }) else { return nil }
        return lines[start...end].joined(separator: "\n")
    }

    /// No class adopts it: every requirement is named from its selector by
    /// the importer's rules, and pinned to it.
    @Test func requirementsNamedFromSelectors() async throws {
        let interface = try await interface(of: SwiftDeclaredObjCProtocolsFixture.machOFile(.full))
        let declaration = try #require(block(startingWith: "@objc protocol DerivedSelectors:", in: interface), "\(interface)")
        for expectedLine in [
            "@objc protocol DerivedSelectors: __C.NSObject {",
            "    // Swift names follow the ClangImporter's rules for these selectors; the binary records no Swift names for them.",
            "    @objc(initWithIdentifier:) init!(identifier: Swift.String!)",
            "    @objc(nameFor:) func name(for: Any!) -> Swift.String!",
            "    @objc(teamNameFor:error:) func teamName(for: Swift.String!) throws -> Swift.String",
            "    @objc(hangPointsWithInput:error:) func hangPoints(input: __C.NSObject!) throws -> [Any]",
            "    @objc(perform:with:) func perform(_: Swift.String!, with: Any!)",
            "    @objc(tokenAndReturnError:) func token() throws -> Swift.String",
            "    @objc(isEnabled) var isEnabled: Swift.Bool {",
            "    @objc(objectAtIndexedSubscript:) subscript(_: Swift.Int) -> Any! {",
            "    @objc(makeDefault) static func makeDefault() -> __C.NSObject!",
            "    @objc(shared) static var shared: __C.NSObject! {",
            "    @objc(scrollTo:animated:) optional func scroll(to: Swift.Int, animated: Swift.Bool)",
            "    @objc(optionalCount) optional var optionalCount: Swift.Int {",
        ] {
            #expect(declaration.contains(expectedLine), "\(expectedLine)\n---\n\(declaration)")
        }
    }

    /// The protocol extension trails its protocol, as a Swift protocol's
    /// does, instead of standing alone among the extensions.
    @Test func protocolExtensionTrailsTheProtocol() async throws {
        let interface = try await interface(of: SwiftDeclaredObjCProtocolsFixture.machOFile(.full))
        let declaration = try #require(block(startingWith: "@objc protocol DerivedSelectors:", in: interface), "\(interface)")
        let trailingExtension = "\(declaration)\nextension \(Self.moduleName).DerivedSelectors {\n    func describe() -> Swift.String\n}"
        #expect(interface.contains(trailingExtension), "\(interface)")
        #expect(interface.components(separatedBy: "extension \(Self.moduleName).DerivedSelectors {").count == 2, "\(interface)")
    }

    /// Implemented by a class of the image: the member's own signature,
    /// with the class it was taken from.
    @Test func requirementsTakenFromConformers() async throws {
        let interface = try await interface(of: SwiftDeclaredObjCProtocolsFixture.machOFile(.full))
        let sameNameRenamed = try #require(block(startingWith: "@objc(SameNameRenamed) protocol SameNameRenamed {", in: interface), "\(interface)")
        #expect(sameNameRenamed.contains("    @objc func ping()"), "\(sameNameRenamed)")
        #expect(sameNameRenamed.contains("    // Taken from the conformer \(Self.moduleName)."), "\(sameNameRenamed)")
        #expect(!sameNameRenamed.contains("ClangImporter"), "\(sameNameRenamed)")

        let refined = try #require(block(startingWith: "@objc protocol RefinedProtocol: \(Self.moduleName).SameNameRenamed {", in: interface), "\(interface)")
        #expect(refined.contains("    // Taken from the conformer \(Self.moduleName).ExtensionConformer.\n    @objc func refine()"), "\(refined)")

        let internalProtocol = try #require(block(startingWith: "@objc protocol InternalProtocol {", in: interface), "\(interface)")
        #expect(internalProtocol.contains("    // Taken from the conformer \(Self.moduleName).InternalConformer.\n    @objc func internalRequirement()"), "\(internalProtocol)")
    }

    /// Renamed to a name other than its Swift name: nothing pairs the
    /// record with it, and the declaration says so.
    @Test func unpairedRenamedProtocol() async throws {
        let interface = try await interface(of: SwiftDeclaredObjCProtocolsFixture.machOFile(.full))
        let declaration = try #require(block(startingWith: "@objc protocol DifferentlyNamed {", in: interface), "\(interface)")
        #expect(declaration.contains("No Objective-C protocol record pairs with this declaration"), "\(declaration)")
    }

    /// File-private: its Swift name carries a private discriminator, which
    /// the header leaves out, as a Swift protocol's does.
    @Test func privateProtocolHeaderPrintsTheBareName() async throws {
        let interface = try await interface(of: SwiftDeclaredObjCProtocolsFixture.machOFile(.full))
        #expect(block(startingWith: "@objc protocol PrivateProtocol {", in: interface) != nil, "\(interface)")
        #expect(!interface.contains("PrivateProtocol in _"), "\(interface)")
    }

    /// Declared in a type: printed in an extension of the type.
    @Test func nestedProtocolPrintsInAnExtensionOfItsParent() async throws {
        let interface = try await interface(of: SwiftDeclaredObjCProtocolsFixture.machOFile(.full))
        let parentExtension = try #require(block(startingWith: "extension \(Self.moduleName).Outer {", in: interface), "\(interface)")
        #expect(parentExtension.contains("    @objc protocol NestedProtocol {"), "\(parentExtension)")
        #expect(parentExtension.contains("        @objc func nestedRequirement()"), "\(parentExtension)")
    }

    /// The protocols another module declares — the kit's, whose records the
    /// client holds copies of — are not declared here.
    @Test func adoptedProtocolsOfAnotherModuleAreNotDeclared() async throws {
        let interface = try await interface(of: SwiftDeclaredObjCProtocolsFixture.machOFile(.full))
        #expect(!interface.contains("protocol KitObserver"), "\(interface)")
        #expect(!interface.contains("protocol RenamedKitObserver"), "\(interface)")
    }

    /// A class's header lists the Objective-C protocols its own data lists —
    /// an extension of its own module's included — named in Swift: another
    /// module's protocol renamed to its own name found through the
    /// dependency closure, one renamed to another name left as it is, and
    /// one a Swift conformance implies left out.
    @Test func classHeadersListAdoptedObjCProtocols() async throws {
        let interface = try await interface(of: SwiftDeclaredObjCProtocolsFixture.machOFile(.full))
        let kitModuleName = SwiftDeclaredObjCProtocolsFixture.kitModuleName
        for expectedHeader in [
            "class Conformer: __C.NSObject, \(Self.moduleName).SameNameRenamed, __C.NSCopying {",
            "class ExtensionConformer: __C.NSObject, \(Self.moduleName).RefinedProtocol {",
            "class KitObserverConformer: __C.NSObject, \(kitModuleName).KitObserver, __C.KITRenamedObserver, \(kitModuleName).KitSameName {",
            "class ImpliedConformer: __C.NSObject {",
        ] {
            #expect(interface.contains("\n\(expectedHeader)"), "\(expectedHeader)\n---\n\(interface)")
        }
        // The implied protocol's Swift conformance prints as before.
        #expect(interface.contains("extension \(Self.moduleName).ImpliedConformer: \(Self.moduleName).CopyingRefinement {}"), "\(interface)")
    }

    /// An extension of another module's class adopting one: its category's
    /// protocol list, as an extension of its own.
    @Test func categoryConformancePrintsAsAnExtension() async throws {
        let interface = try await interface(of: SwiftDeclaredObjCProtocolsFixture.machOFile(.full))
        #expect(interface.contains("\nextension __C.NSDateFormatter: \(Self.moduleName).SameNameRenamed {}"), "\(interface)")
    }

    /// The in-process image prints the same declarations.
    @Test func loadedImageMatchesTheFile() async throws {
        let fileInterface = try await interface(of: SwiftDeclaredObjCProtocolsFixture.machOFile(.full))
        let imageInterface = try await interface(of: SwiftDeclaredObjCProtocolsFixture.loadedImage())
        for prefix in ["@objc protocol DerivedSelectors:", "@objc(SameNameRenamed) protocol SameNameRenamed {", "@objc protocol RefinedProtocol:", "@objc protocol InternalProtocol {", "extension \(Self.moduleName).Outer {", "class Conformer:", "class KitObserverConformer:"] {
            let fileBlock = block(startingWith: prefix, in: fileInterface)
            #expect(fileBlock != nil, "\(prefix)")
            #expect(fileBlock == block(startingWith: prefix, in: imageInterface), "\(prefix)")
        }
        #expect(imageInterface.contains("\nextension __C.NSDateFormatter: \(Self.moduleName).SameNameRenamed {}"), "\(imageInterface)")
    }
}
