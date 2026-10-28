import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
@testable import SwiftDump
import SwiftDeclarationRendering
@_spi(Internals) import SwiftInspection
@testable import MachOTestingSupport

/// The dump of an `@objc` protocol declared in Swift (evolution proposal
/// `swift-declared-objc-protocols`): each requirement as a Swift declaration
/// with its Objective-C facts — selector, required or optional, type
/// encoding, and the class it was taken from when one implements it.
@Suite(.serialized, ExclusiveImageAccess(SwiftDeclaredObjCProtocolsFixture.moduleName))
struct SwiftDeclaredObjCProtocolDumpTests {
    private static let moduleName = SwiftDeclaredObjCProtocolsFixture.moduleName

    private func dump(of name: String, in machOFile: MachOFile) async throws -> String {
        ObjCAncestorResolverStore.shared.register(ObjCAncestorResolver(root: machOFile, searchPaths: try SwiftDeclaredObjCProtocolsFixture.dependencySearchPaths()), for: machOFile)
        defer { ObjCAncestorResolverStore.shared.remove(for: machOFile) }
        let declaredProtocol = try #require(SwiftDeclaredObjCProtocol.all(in: machOFile).first { $0.qualifiedName == "\(Self.moduleName).\(name)" }, "\(name) not found")
        return try await declaredProtocol.dump(using: .demangleOptions(.test), in: machOFile).string
    }

    @Test func requirementsNamedFromSelectorsCarryTheirObjCFacts() async throws {
        let output = try await dump(of: "DerivedSelectors", in: SwiftDeclaredObjCProtocolsFixture.machOFile(.full))
        // The test options print imported names without `__C`.
        #expect(output.contains("@objc protocol \(Self.moduleName).DerivedSelectors: NSObject {"), "\(output)")
        #expect(output.contains("// Evidence: field descriptor of kind ObjCProtocol at 0x"), "\(output)")
        #expect(output.contains("// ObjC protocol _TtP\(Self.moduleName.count)\(Self.moduleName)16DerivedSelectors_, record emitted by Swift at 0x"), "\(output)")
        #expect(output.contains("// Requirements no class of this image implements are named from their selectors"), "\(output)")
        #expect(output.contains("@objc(teamNameFor:error:) \(Self.moduleName).DerivedSelectors.teamName(for: "), "\(output)")
        #expect(output.contains(" throws -> Swift.String // -teamNameFor:error: required, @\"NSString\"32@0:8@\"NSString\"16^@24"), "\(output)")
        #expect(output.contains("// -isEnabled, -setIsEnabled: required, TB,N"), "\(output)")
        #expect(output.contains("// +makeDefault required, @\"NSObject\"16@0:8"), "\(output)")
        #expect(output.contains("@objc(scrollTo:animated:) optional \(Self.moduleName).DerivedSelectors.scroll(to: Swift.Int, animated: Swift.Bool) -> () // -scrollTo:animated: optional, v28@0:8q16B24"), "\(output)")
    }

    /// Implemented by a class of the image: the member's signature, declared
    /// in the protocol, with the class and the evidence that tied it.
    @Test func requirementsTakenFromConformersNameTheClass() async throws {
        let output = try await dump(of: "RefinedProtocol", in: SwiftDeclaredObjCProtocolsFixture.machOFile(.full))
        #expect(output.contains("@objc protocol \(Self.moduleName).RefinedProtocol: \(Self.moduleName).SameNameRenamed {"), "\(output)")
        #expect(output.contains("@objc \(Self.moduleName).RefinedProtocol.refine() -> () // -refine required, v16@0:8; implemented by \(Self.moduleName).ExtensionConformer (To thunk symbol at the IMP)"), "\(output)")
        #expect(!output.contains("ClangImporter"), "\(output)")
    }

    /// Stripped, the thunk's code ties the member instead of its symbol.
    @Test func strippedConformersAreTiedThroughTheThunkCode() async throws {
        let output = try await dump(of: "RefinedProtocol", in: SwiftDeclaredObjCProtocolsFixture.machOFile(.strippedLocals))
        #expect(output.contains("implemented by \(Self.moduleName).ExtensionConformer (the IMP's code references the implementation)"), "\(output)")
    }

    @Test func unpairedRenamedProtocolSaysSo() async throws {
        let output = try await dump(of: "DifferentlyNamed", in: SwiftDeclaredObjCProtocolsFixture.machOFile(.full))
        #expect(output.contains("@objc protocol \(Self.moduleName).DifferentlyNamed {"), "\(output)")
        #expect(output.contains("// No Objective-C protocol record pairs with this declaration"), "\(output)")
    }

    /// The records no declaration claims: this image's renamed-away one,
    /// and the kit's renamed protocols it references — the one renamed to
    /// its own name found in the kit.
    @Test func unclaimedRecordsAreListed() async throws {
        let machOFile = try SwiftDeclaredObjCProtocolsFixture.machOFile(.full)
        ObjCAncestorResolverStore.shared.register(ObjCAncestorResolver(root: machOFile, searchPaths: try SwiftDeclaredObjCProtocolsFixture.dependencySearchPaths()), for: machOFile)
        defer { ObjCAncestorResolverStore.shared.remove(for: machOFile) }
        let comment = try #require(try await SwiftDeclaredObjCProtocol.unclaimedRecordsComment(using: DumperConfiguration.demangleOptions(.test).demangleResolver, in: machOFile))
        #expect(comment.contains("PRBDifferentlyNamed"), "\(comment)")
        #expect(comment.contains("KITRenamedObserver,"), "\(comment)")
        #expect(comment.contains("KitSameName → \(SwiftDeclaredObjCProtocolsFixture.kitModuleName).KitSameName"), "\(comment)")
    }
}
