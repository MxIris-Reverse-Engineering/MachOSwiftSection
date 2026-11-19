import Foundation
import Testing
@_spi(Internals) import MachOSymbols
@testable import SwiftSymbols

/// What the Swift store hands MachOKitExtensions' symbol sweep: Swift-mangled
/// names into the demangled, offset-indexed table, the linker de-duplication
/// names into their own name-only table, and nothing else.
@Suite
struct SwiftSymbolTableRoutingTests {
    private let routing = SwiftSymbolTableRouting()

    private func table(forSymbolNamed name: String) -> SwiftSymbolTableRouting.Table? {
        name.withCString { routing.table(forSymbolNamed: $0, language: SymbolLanguage(ofSymbolNameBytes: $0)) }
    }

    @Test func swiftRoutingFilesSymbolicManglingNamesIntoTheirOwnTable() {
        #expect(table(forSymbolNamed: "$s7SwiftUI4TextVMn") == .swift)
        #expect(table(forSymbolNamed: "_$s7SwiftUI4TextVMn") == .swift)
        #expect(table(forSymbolNamed: "_symbolic _____ 7SwiftUI4TextV") == .symbolicMangling)
        #expect(table(forSymbolNamed: "_default assoc type _____y_____") == .symbolicMangling)
    }

    @Test func swiftRoutingLeavesOtherLanguagesOut() {
        #expect(table(forSymbolNamed: "_malloc") == nil)
        #expect(table(forSymbolNamed: "__ZN4llvm5Value4dumpEv") == nil)
        #expect(table(forSymbolNamed: "-[NSView setNeedsDisplay:]") == nil)
        #expect(table(forSymbolNamed: "_OBJC_CLASS_$__TtC7SwiftUI14NSHostingView") == nil)
    }

    /// The routing reads names with this package's own rules, whatever
    /// language the sweep's registry handed it.
    @Test func swiftRoutingDoesNotDependOnTheRegisteredLanguage() {
        let swiftTable = "_$s7SwiftUI4TextVMn".withCString { routing.table(forSymbolNamed: $0, language: .c) }
        #expect(swiftTable == .swift)
        let cTable = "_malloc".withCString { routing.table(forSymbolNamed: $0, language: .swift) }
        #expect(cTable == nil)
    }

    @Test func onlyTheSwiftTableIsIndexedByOffset() {
        #expect(routing.offsetIndexing(in: .swift) == .byOffset)
        #expect(routing.offsetIndexing(in: .symbolicMangling) == .nameOnly)
        #expect(routing.mayReferenceStringTablesOfLoadedImages)
    }
}
