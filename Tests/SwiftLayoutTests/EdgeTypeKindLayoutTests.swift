import Foundation
import Testing
import MachOKit
import Demangling
@testable import MachOSwiftSection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Covers the edge function-reference type kinds the resolver now models as a
/// single pointer: C function pointers (`@convention(c)`/`@convention(thin)`)
/// and Objective-C blocks (`@convention(block)`), distinct from the thick Swift
/// `.functionType` (16 bytes). The resolver dispatches purely on `Node.Kind`, so
/// a minimal constructed node exercises the path.
@Suite
final class EdgeTypeKindLayoutTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    @MainActor
    @Test(arguments: [Node.Kind.cFunctionPointer, .objCBlock, .escapingObjCBlock])
    func singlePointerFunctionKindsAreOneWord(kind: Node.Kind) throws {
        let universe = try ImageUniverse.singleImage(machOImage)
        let resolver = StaticTypeLayoutResolver(imageUniverse: universe)
        let layout = try resolver.layout(forTypeNode: Node.create(kind: kind), in: universe.rootImage)
        #expect(layout.size == 8, "\(kind) should be one pointer (8 bytes)")
        #expect(layout.stride == 8)
        #expect(layout.alignmentMask == 7)
    }

    /// Guard the distinction from the thick Swift function value (function +
    /// context = 16 bytes), so the two paths do not collapse.
    @MainActor
    @Test func thickSwiftFunctionRemainsTwoWords() throws {
        let universe = try ImageUniverse.singleImage(machOImage)
        let resolver = StaticTypeLayoutResolver(imageUniverse: universe)
        let layout = try resolver.layout(forTypeNode: Node.create(kind: .functionType), in: universe.rootImage)
        #expect(layout.size == 16)
    }
}
