import Foundation
import Testing
import MachOKit
import Demangling
@testable import MachOSwiftSection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Covers existentials over imported Objective-C protocols (`any NSCopying`),
/// which have no Swift protocol descriptor. An ObjC protocol is always
/// class-bound and contributes no Swift witness table, so `any <ObjCProto>` is a
/// single class reference (8 bytes) and a mixed composition is class-bound with
/// only the Swift protocols counted.
@Suite
final class ObjCProtocolExistentialTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    /// `__C.<Name>` protocol node → bare name; a Swift protocol node → nil.
    @Test func objCProtocolBareNameDetectsImportedProtocols() {
        let objCProtocol = Self.protocolNode(module: "__C", identifier: "NSCopying")
        #expect(NodeTypeNaming.objCProtocolBareName(of: objCProtocol) == "NSCopying")
        #expect(NodeTypeNaming.objCProtocolBareName(of: Node.create(kind: .type, child: objCProtocol)) == "NSCopying")

        let swiftProtocol = Self.protocolNode(module: "MyModule", identifier: "MyProtocol")
        #expect(NodeTypeNaming.objCProtocolBareName(of: swiftProtocol) == nil)
    }

    /// `any NSCopying` (a pure ObjC protocol existential) is class-bound with no
    /// witness table → a single object word (8 bytes).
    @MainActor
    @Test func pureObjCProtocolExistentialIsOneWord() throws {
        let universe = try ImageUniverse.singleImage(machOImage)
        let resolver = StaticTypeLayoutResolver(imageUniverse: universe)
        let existential = Self.existentialNode(protocols: [
            Self.protocolNode(module: "__C", identifier: "NSCopying"),
        ])
        let layout = try resolver.existentialLayout(forNode: existential, in: universe.rootImage)
        #expect(layout.size == 8, "any NSCopying should be a single class reference")
        #expect(layout.alignmentMask == 7)
    }

    /// `any NSCopying & NSCoding` (two ObjC protocols) is still a single class
    /// reference — neither contributes a witness table.
    @MainActor
    @Test func multipleObjCProtocolExistentialIsOneWord() throws {
        let universe = try ImageUniverse.singleImage(machOImage)
        let resolver = StaticTypeLayoutResolver(imageUniverse: universe)
        let existential = Self.existentialNode(protocols: [
            Self.protocolNode(module: "__C", identifier: "NSCopying"),
            Self.protocolNode(module: "__C", identifier: "NSCoding"),
        ])
        let layout = try resolver.existentialLayout(forNode: existential, in: universe.rootImage)
        #expect(layout.size == 8)
    }

    /// A composition mixing an ObjC protocol with an opaque Swift protocol is
    /// forced class-bound by the ObjC protocol, and counts only the Swift
    /// protocol's witness table → 1 object word + 1 witness word (16 bytes).
    /// (`any ProtocolTest` alone is the opaque 40-byte form, so this proves the
    /// ObjC protocol flips the representation to class-bound.)
    @MainActor
    @Test func mixedObjCAndSwiftProtocolExistentialIsClassBound() throws {
        let universe = try ImageUniverse.singleImage(machOImage)
        let resolver = StaticTypeLayoutResolver(imageUniverse: universe)
        let existential = Self.existentialNode(protocols: [
            Self.protocolNode(module: "__C", identifier: "NSCopying"),
            Self.swiftProtocolTestNode(),
        ])
        let layout = try resolver.existentialLayout(forNode: existential, in: universe.rootImage)
        #expect(layout.size == 16, "ObjC protocol forces class-bound; the Swift protocol adds one witness word")
    }

    // MARK: - Node construction

    private static func protocolNode(module: String, identifier: String) -> Node {
        Node.create(kind: .protocol, children: [
            Node.create(kind: .module, text: module),
            Node.create(kind: .identifier, text: identifier),
        ])
    }

    /// `SymbolTestsCore.Protocols.ProtocolTest` — a nested (enum-namespaced)
    /// opaque Swift protocol the fixture defines, resolvable via the image's
    /// `__swift5_protos` class-constraint index.
    private static func swiftProtocolTestNode() -> Node {
        Node.create(kind: .protocol, children: [
            Node.create(kind: .enum, children: [
                Node.create(kind: .module, text: "SymbolTestsCore"),
                Node.create(kind: .identifier, text: "Protocols"),
            ]),
            Node.create(kind: .identifier, text: "ProtocolTest"),
        ])
    }

    private static func existentialNode(protocols: [Node]) -> Node {
        Node.create(kind: .protocolList, children: [
            Node.create(kind: .typeList, children: protocols.map { Node.create(kind: .type, child: $0) }),
        ])
    }
}
