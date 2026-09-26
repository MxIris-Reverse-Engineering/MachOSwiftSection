import Foundation
import Testing
import MachOKit
import Demangling
@testable import MachOSwiftSection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport

/// `Builtin.Borrow<Referent>` (Swift 6.4, the storage behind `Swift.Ref`) is
/// laid out inline like its referent unless the referent is larger than four
/// words, addressable-for-dependencies, or not bitwise-borrowable — then it is
/// one raw pointer. The expected values below are the rule of the runtime's
/// `swift_getBorrowRepresentation` (`Borrow.cpp`) applied by hand; the host
/// runtime (macOS 26) has no borrow metadata to compare against, so these are
/// literal expectations, not a round trip.
@Suite
final class BorrowLayoutTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    @MainActor
    private func resolveLayout(ofMangledType mangledTypeName: String) throws -> StaticTypeLayout {
        let universe = try ImageUniverse.singleImage(machOImage)
        let resolver = StaticTypeLayoutResolver(imageUniverse: universe)
        let typeNode = try demangleAsNode(mangledTypeName, isType: true)
        try #require(typeNode.firstChild?.kind == .builtinBorrow, "\(mangledTypeName) should demangle to Builtin.Borrow")
        return try resolver.layout(forTypeNode: typeNode, in: universe.rootImage)
    }

    /// `Builtin.Borrow<Int>`: `Int` is one word, bitwise-borrowable and not
    /// addressable-for-dependencies, so the borrow *is* an `Int` bit-for-bit.
    @MainActor
    @Test func borrowOfOneWordScalarIsInline() throws {
        let layout = try resolveLayout(ofMangledType: "SiBW")
        #expect(layout.size == 8)
        #expect(layout.stride == 8)
        #expect(layout.alignmentMask == 7)
        #expect(layout.extraInhabitantCount == 0)
        #expect(layout.isBitwiseBorrowable == true)
        #expect(layout.isAddressableForDependencies == false)
    }

    /// `Builtin.Borrow<String>`: two words, still inline, and the borrow keeps
    /// the referent's extra inhabitants (`Optional<Builtin.Borrow<String>>`
    /// needs no tag byte, exactly like `String?`).
    @MainActor
    @Test func borrowOfTwoWordStructIsInlineAndKeepsExtraInhabitants() throws {
        let layout = try resolveLayout(ofMangledType: "SSBW")
        let stringLayout = try #require(KnownLayoutTable.layout(forFullyQualifiedTypeName: "Swift.String"))
        #expect(layout.size == 16)
        #expect(layout.extraInhabitantCount == stringLayout.extraInhabitantCount)
    }

    /// `Builtin.Borrow<(Int, Int, Int, Int, Int)>`: five words exceed the
    /// four-pointer inline budget, so the borrow degrades to a single raw
    /// pointer with the pointer's one extra inhabitant (null).
    @MainActor
    @Test func borrowOfMoreThanFourWordsIsAPointer() throws {
        let layout = try resolveLayout(ofMangledType: "Si_S4itBW")
        #expect(layout.size == 8)
        #expect(layout.stride == 8)
        #expect(layout.alignmentMask == 7)
        #expect(layout.extraInhabitantCount == 1)
    }

    /// `Builtin.Borrow<(Int, Int, Int, Int)>`: exactly four words is the
    /// largest inline borrow.
    @MainActor
    @Test func borrowOfExactlyFourWordsStaysInline() throws {
        let layout = try resolveLayout(ofMangledType: "Si_S3itBW")
        #expect(layout.size == 32)
        #expect(layout.stride == 32)
    }

    /// `Builtin.Borrow<InlineArray<2, Int>>`: two words, but a fixed array is
    /// addressable-for-dependencies, which forces the pointer representation
    /// regardless of size.
    @MainActor
    @Test func borrowOfAddressableForDependenciesReferentIsAPointer() throws {
        let inlineArrayLayout = try resolveLayout(ofMangledType: "s11InlineArrayVy$1_SiGBW")
        #expect(inlineArrayLayout.size == 8)
        #expect(inlineArrayLayout.extraInhabitantCount == 1)
    }

    /// The fixed-array flag the previous test relies on is a fact of the
    /// referent, not of the borrow: `InlineArray<2, Int>` itself reports it.
    @MainActor
    @Test func fixedArrayIsAddressableForDependencies() throws {
        let universe = try ImageUniverse.singleImage(machOImage)
        let resolver = StaticTypeLayoutResolver(imageUniverse: universe)
        let typeNode = try demangleAsNode("s11InlineArrayVy$1_SiG", isType: true)
        let layout = try resolver.layout(forTypeNode: typeNode, in: universe.rootImage)
        #expect(layout.size == 16)
        #expect(layout.isAddressableForDependencies == true)
        #expect(layout.isBitwiseBorrowable == true)
    }

    /// A borrow of a borrow is inline over the inner borrow's representation.
    @MainActor
    @Test func borrowOfBorrowIsInline() throws {
        let layout = try resolveLayout(ofMangledType: "SiBWBW")
        #expect(layout.size == 8)
        #expect(layout.extraInhabitantCount == 0)
    }
}
