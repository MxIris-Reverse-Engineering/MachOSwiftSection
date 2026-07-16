import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport
import Demangling

/// Validates the two resolution paths added on top of phase 7: nested types
/// whose fields use the *specialized parent's* generic arguments (the
/// arguments ride the parent context in the mangling —
/// `ParentArgumentUser<Bool>.Content`, the `SwiftUI.Environment` shape; the
/// generic multi-payload instantiation also checks the runtime's
/// tagged-layout extra inhabitants through `optionalContent`), and
/// existentials over Swift-declared `@objc` protocols (which emit no Swift
/// protocol descriptor and are recognized via `__objc_protolist`). Every
/// holder is non-generic, so its runtime field-offset vector is the ground
/// truth. Verified on the in-process reader and the offline `MachOFile`
/// reader — both in single-image scope, since every referenced declaration
/// lives in the fixture image or the frozen stdlib table.
@Suite
final class NestedParentArgumentAndObjCProtocolLayoutTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    private static let fullyResolvingHolders = [
        "NestedParentArgumentFieldHolder",
        "MultiLevelNestedFieldHolder",
        "ObjCProtocolExistentialFieldHolder",
    ]

    @MainActor
    @Test func holdersFullyResolveAndMatchRuntime() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)
        let fileCalculator = try StaticLayoutCalculator(machO: machOFile)

        for shortName in Self.fullyResolvingHolders {
            let qualifiedTypeName = "SymbolTestsCore.GenericFieldLayout.\(shortName)"
            let runtimeOffsets = try #require(
                try runtimeFieldOffsets(ofQualifiedTypeName: qualifiedTypeName, in: machO),
                "no runtime field-offset vector for \(qualifiedTypeName)"
            )
            let aggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: calculator, in: machO)
            assertFullyComputed(aggregate, equals: runtimeOffsets, typeName: qualifiedTypeName)

            let fileAggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: fileCalculator, in: machOFile)
            assertFullyComputed(fileAggregate, equals: runtimeOffsets, typeName: "\(qualifiedTypeName) (MachOFile)")
        }
    }

    /// The parent-chain environment, on the raw node shapes: a plain nominal
    /// node whose *context* is a bound generic binds the parent's arguments at
    /// depth 0, and a two-level nested instantiation binds each level at its
    /// own depth (outermost = 0).
    @Test func parentChainArgumentsBindAtTheirDepths() {
        // Enum(BoundGenericStructure(Environment, TypeList(Bool)), Content) —
        // the nested type carries no argument list of its own.
        let specializedParent = Node.create(kind: .boundGenericStructure, children: [
            Node.create(kind: .type, child: Node.create(kind: .structure, children: [
                Node.create(kind: .module, text: "SwiftUI"),
                Node.create(kind: .identifier, text: "Environment"),
            ])),
            Node.create(kind: .typeList, children: [Self.swiftStructTypeNode("Bool")]),
        ])
        let nestedEnum = Node.create(kind: .enum, children: [
            specializedParent,
            Node.create(kind: .identifier, text: "Content"),
        ])
        let environment = GenericArgumentEnvironment.make(forInstantiatedTypeNode: nestedEnum)
        let substituted = environment.substituting(in: Self.dependentGenericParamTypeNode(depth: 0, index: 0))
        #expect(substituted.kind == .structure && substituted.identifier == "Bool",
                "the parent's argument must bind at depth 0")

        // BoundGenericStructure(Structure(BoundGenericStructure(Outer<Int8>),
        // Inner), TypeList(Int64)) — one argument list per level.
        let outerLevel = Node.create(kind: .boundGenericStructure, children: [
            Node.create(kind: .type, child: Node.create(kind: .structure, children: [
                Node.create(kind: .module, text: "MyModule"),
                Node.create(kind: .identifier, text: "Outer"),
            ])),
            Node.create(kind: .typeList, children: [Self.swiftStructTypeNode("Int8")]),
        ])
        let innerNominal = Node.create(kind: .structure, children: [
            outerLevel,
            Node.create(kind: .identifier, text: "Inner"),
        ])
        let innerLevel = Node.create(kind: .boundGenericStructure, children: [
            Node.create(kind: .type, child: innerNominal),
            Node.create(kind: .typeList, children: [Self.swiftStructTypeNode("Int64")]),
        ])
        let twoLevelEnvironment = GenericArgumentEnvironment.make(forInstantiatedTypeNode: innerLevel)
        let outerSubstituted = twoLevelEnvironment.substituting(in: Self.dependentGenericParamTypeNode(depth: 0, index: 0))
        let innerSubstituted = twoLevelEnvironment.substituting(in: Self.dependentGenericParamTypeNode(depth: 1, index: 0))
        #expect(outerSubstituted.identifier == "Int8", "the outer level's argument must bind at depth 0")
        #expect(innerSubstituted.identifier == "Int64", "the inner level's argument must bind at depth 1")
    }

    /// The legacy `_TtP<module><name>_` protocol-mangling parser behind the
    /// `__objc_protolist` index: the two-component form parses, everything
    /// else (native ObjC names, malformed lengths) is skipped.
    @Test func legacyObjCProtocolManglingParses() {
        #expect(
            ObjCProtocolIndex.swiftQualifiedName(
                fromLegacyProtocolMangledName: "_TtP7SwiftUI36PlatformAccessibilityElementProtocol_"
            ) == "SwiftUI.PlatformAccessibilityElementProtocol"
        )
        #expect(
            ObjCProtocolIndex.swiftQualifiedName(
                fromLegacyProtocolMangledName: "_TtP15SymbolTestsCore23ObjCOnlyElementProtocol_"
            ) == "SymbolTestsCore.ObjCOnlyElementProtocol"
        )
        #expect(ObjCProtocolIndex.swiftQualifiedName(fromLegacyProtocolMangledName: "NSCopying") == nil)
        #expect(ObjCProtocolIndex.swiftQualifiedName(fromLegacyProtocolMangledName: "_TtP7SwiftUI99Truncated_") == nil)
    }

    // MARK: - Node construction

    private static func swiftStructTypeNode(_ identifier: String) -> Node {
        Node.create(kind: .type, child: Node.create(kind: .structure, children: [
            Node.create(kind: .module, text: "Swift"),
            Node.create(kind: .identifier, text: identifier),
        ]))
    }

    private static func dependentGenericParamTypeNode(depth: UInt64, index: UInt64) -> Node {
        Node.create(kind: .dependentGenericParamType, children: [
            Node.create(kind: .index, index: depth),
            Node.create(kind: .index, index: index),
        ])
    }
}
