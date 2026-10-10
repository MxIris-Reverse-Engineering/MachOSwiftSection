import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftThunkAnalysis
import MachOTestingSupport

/// An accessor thunk reads its owner's generic arguments out of one buffer,
/// and `AccessorThunkOwnerLayout` names the k-th word as the parameter it
/// carries — by `(depth, index)`, the coordinates the thunk's type nodes are
/// built with and the field records use. A depth counts only the contexts
/// that declare parameters.
///
/// The layout used to open a depth for every generic ancestor, so
/// `InnerElement` in `DepthOuter<OuterElement>.Middle.Inner<InnerElement>` —
/// the second word — read as `(2, 0)`, a
/// parameter no field names, instead of `(1, 0)`.
@Suite
struct AccessorThunkOwnerLayoutDepthTests {
    @Test("a word behind a level that declares no parameter names the next depth")
    func wordBehindNonDeclaringLevel() throws {
        let machOFile = try GenericSpecializationFixture.machOFile()
        let descriptor = try GenericSpecializationFixture.typeContextDescriptor(named: "Inner", in: machOFile)
        let layout = AccessorThunkOwnerLayout(genericContext: try descriptor.genericContext(in: machOFile.context))

        let firstPosition = try #require(layout.genericParameterPosition(ofKeyArgumentAt: 0))
        let secondPosition = try #require(layout.genericParameterPosition(ofKeyArgumentAt: 1))
        #expect(firstPosition.depth == 0 && firstPosition.index == 0)
        #expect(secondPosition.depth == 1 && secondPosition.index == 0)
    }
}
