import Foundation
import Testing
import Demangling
import MachOReading
import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import CrossReferenceAnalysis

/// A type of this test bundle that nothing else names: its key comes from
/// its `…Mn` symbol. Internal, so that no private discriminator joins it.
struct TransientDescriptorKeyProbe {}

/// A type query demangles names nothing bounds — every accessor symbol and
/// mangled name a scan meets — so none of them may stay behind in a cache the
/// process never evicts: the shared `NodeCache`, or the memo an in-process
/// `SymbolicDemangler.demangleType(for:in:)` fills.
@Suite(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
struct TypeNameRetentionTests {
    private var analyzer: CrossReferenceAnalyzer { SharedAnalyzer.analyzer! }

    /// A type key no other name in the process spells: module `M`, and an
    /// identifier with 32 random letters.
    private static func uniqueTypeKey() -> (key: String, identifier: String) {
        let letters = UUID().uuidString.compactMap(\.hexDigitValue).map { Character(UnicodeScalar(UInt8(ascii: "a") + UInt8($0))) }
        let identifier = "TransientProbe" + String(letters)
        return ("1M\(identifier.utf8.count)\(identifier)V", identifier)
    }

    /// Whether the shared `NodeCache` held an identifier leaf spelling
    /// `text`: interning one it already holds leaves its count as it was.
    /// Interning elsewhere in the process can make a held leaf look new,
    /// never a new one look held.
    private static func sharedNodeCacheHoldsIdentifier(_ text: String) -> Bool {
        let count = NodeCache.shared.count
        _ = NodeCache.shared.intern(kind: .identifier, text: text)
        return NodeCache.shared.count == count
    }

    @Test func anAccessorSymbolLeavesNoTreeBehind() {
        let (key, identifier) = Self.uniqueTypeKey()
        #expect(analyzer.swiftTypeKeys(in: .accessorSymbol("$s\(key)Ma")) == [key])
        #expect(!Self.sharedNodeCacheHoldsIdentifier(identifier))
    }

    @Test func aMangledNameLeavesNoTreeBehind() throws {
        let (key, identifier) = Self.uniqueTypeKey()
        let buffer = try #require(strdup(key))
        defer { free(buffer) }
        // Any image's slide turns the buffer's address into a location.
        let slide = try #require(analyzer.images[0].vmaddrSlide)
        let location = CodeLocation(imageIndex: 0, address: UInt64(bitPattern: Int64(Int(bitPattern: buffer)) &- Int64(slide)))
        #expect(analyzer.swiftTypeKeys(in: .mangledName(location: location, length: key.utf8.count)) == [key])
        let mangledName = try MangledName.resolve(at: UnsafeRawPointer(buffer), in: InProcessContext.shared)
        #expect(!SymbolicDemangler.processScopedMemoHoldsType(for: mangledName))
        #expect(!Self.sharedNodeCacheHoldsIdentifier(identifier))
    }

    @Test func aDescriptorSymbolLeavesNoTreeBehind() throws {
        let imageIndex = try #require(analyzer.images.firstIndex { $0.ptr == #dsohandle }, "the test bundle is not among the images")
        let key = try #require(_mangledTypeName(TransientDescriptorKeyProbe.self))
        let location = try #require(analyzer.swiftTypeDescriptorLocations(withKey: key, inImageAt: imageIndex).first)
        #expect(analyzer.swiftTypeIdentity(ofDescriptorAt: location)?.key == key)
        #expect(!Self.sharedNodeCacheHoldsIdentifier("TransientDescriptorKeyProbe"))
    }
}
