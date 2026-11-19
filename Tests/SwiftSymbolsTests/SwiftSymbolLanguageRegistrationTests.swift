import Foundation
import Testing
import MachOKit
@_spi(Internals) import MachOSymbols
@testable import SwiftSymbols

/// `SymbolLanguage.swift` is this package's: defined in SwiftSymbols,
/// recognized here, and registered with MachOKitExtensions when the image
/// loads — after which MachOKitExtensions' C/C++ index keeps only where
/// Swift symbols sit.
@Suite
struct SwiftSymbolLanguageRegistrationTests {
    /// Defined, non-debug symbols of libswiftCore, split by this package's
    /// Swift rules.
    private static func swiftCoreSymbols() throws -> (image: MachOImage, swift: [MachOImage.Symbol], other: [MachOImage.Symbol]) {
        let swiftCore = try #require(MachOImage(name: "libswiftCore"))
        let defined = swiftCore.symbols.filter { !$0.nlist.isExternal && !$0.nlist.isDebuggingEntry }
        let swift = defined.filter { $0.name.withCString(SwiftSymbolNameRecognition.recognizes) }
        let other = defined.filter { !$0.name.withCString(SwiftSymbolNameRecognition.recognizes) }
        return (swiftCore, swift, other)
    }

    /// No test calls the registration: `SwiftSymbolsRegistration`'s
    /// constructor ran when this test bundle loaded.
    @Test func swiftLanguageIsRegisteredAtLoad() {
        #expect(SymbolLanguageRegistry.shared.registeredLanguages.contains(.swift))
        #expect(SymbolLanguage(ofSymbolNamed: "_$s7SwiftUI4TextVMn") == .swift)
        #expect(SymbolLanguage(ofSymbolNamed: "_symbolic _____ 7SwiftUI4TextV") == .swift)
        #expect(SymbolLanguage(ofSymbolNamed: "__ZN4llvm5Value4dumpEv") == .cPlusPlus)
    }

    @Test func cAndCPlusPlusStoreLeavesSwiftNamesOut() throws {
        let (swiftCore, swiftSymbols, otherSymbols) = try Self.swiftCoreSymbols()
        try #require(!swiftSymbols.isEmpty && !otherSymbols.isEmpty)
        let store = SymbolIndexStore.shared
        #expect(swiftSymbols.filter { store.containsSymbol(named: $0.name, in: swiftCore) }.isEmpty)
        // Every other name is C or C++ — or a language another package
        // linked into this test process registered; those stay out too.
        let unfiledOtherNames = otherSymbols.filter { !store.containsSymbol(named: $0.name, in: swiftCore) }.map(\.name)
        #expect(unfiledOtherNames.allSatisfy { [.c, .cPlusPlus].contains(SymbolLanguage(ofSymbolNamed: $0)) == false }, "\(unfiledOtherNames.prefix(3))")
    }

    /// At the start of a Swift function no C symbol shares, the store
    /// answers `nil` rather than the C function before it.
    @Test func cAndCPlusPlusStoreAnswersNilInsideASwiftFunction() throws {
        let (swiftCore, swiftSymbols, _) = try Self.swiftCoreSymbols()
        let store = SymbolIndexStore.shared
        let swiftOnlyOffsets = Set(swiftSymbols.map(\.offset)).sorted().prefix(2000).filter { store.symbols(for: $0, in: swiftCore) == nil }
        try #require(!swiftOnlyOffsets.isEmpty)
        let answeredOffsets = swiftOnlyOffsets.filter { store.closestSymbols(at: $0, in: swiftCore) != nil }
        #expect(answeredOffsets.isEmpty, "\(answeredOffsets.prefix(3))")
    }
}
