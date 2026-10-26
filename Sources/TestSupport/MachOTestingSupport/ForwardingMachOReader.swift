import Foundation
import MachOKit
import MachOKitExtensions
import MachOReading
import MachOSwiftSection

/// Whether a ``ForwardingMachOReader`` tells the library what it wraps.
package protocol ForwardingMachOReaderDeclaration: Sendable {}

/// The reader declares the reader it forwards to — a host's wrapper that
/// adopted `MachOReaderWrapper`.
package enum DeclaredWrapper: ForwardingMachOReaderDeclaration {}

/// The reader forwards every read and says nothing about it — a host's
/// wrapper written before `MachOReaderWrapper` existed.
package enum UndeclaredWrapper: ForwardingMachOReaderDeclaration {}

/// A reader that forwards every requirement to `base` and adds nothing.
///
/// The shape of a host's wrapper type — MachOKitUI's `MachOImageSource` and
/// `MachOFileSource` hold a `MachOImage` / `MachOFile` for their UI and
/// forward the reading protocols to it — so a test can read an image through
/// the wrapper and through `base` and expect the same answers. Every
/// requirement is forwarded, the defaulted ones too, so nothing a default
/// implementation computes differently from `base`'s own can tell the two
/// apart.
package struct ForwardingMachOReader<Base: MachOSwiftSectionRepresentableWithCache, Declaration: ForwardingMachOReaderDeclaration>: MachOSwiftSectionRepresentableWithCache {
    package let base: Base

    package init(_ base: Base) {
        self.base = base
    }
}

// MARK: - MachORepresentable

extension ForwardingMachOReader {
    package typealias LoadCommands = Base.LoadCommands
    package typealias Symbol = Base.Symbol
    package typealias Symbols64 = Base.Symbols64
    package typealias Symbols = Base.Symbols
    package typealias IndirectSymbols = Base.IndirectSymbols
    package typealias CFStrings32 = Base.CFStrings32
    package typealias CFStrings64 = Base.CFStrings64
    package typealias RebaseOperations = Base.RebaseOperations
    package typealias BindOperations = Base.BindOperations
    package typealias ExportTrie = Base.ExportTrie
    package typealias Strings = Base.Strings
    package typealias UTF16Strings = Base.UTF16Strings
    package typealias FunctionStarts = Base.FunctionStarts
    package typealias DataInCode = Base.DataInCode
    package typealias DyldChainedFixups = Base.DyldChainedFixups
    package typealias ExternalRelocations = Base.ExternalRelocations
    package typealias CodeSign = Base.CodeSign

    package var is64Bit: Bool { base.is64Bit }
    package var headerSize: Int { base.headerSize }
    package var header: MachHeader { base.header }
    package var loadCommands: LoadCommands { base.loadCommands }
    package var endian: Endian { base.endian }
    package var rpaths: [String] { base.rpaths }
    package var dependencies: [DependedDylib] { base.dependencies }
    package var segments: [any SegmentCommandProtocol] { base.segments }
    package var segments64: AnySequence<SegmentCommand64> { base.segments64 }
    package var segments32: AnySequence<SegmentCommand> { base.segments32 }
    package var preferredLoadAddress: UInt64? { base.preferredLoadAddress }
    package var sections: [any SectionProtocol] { base.sections }
    package var sections64: [Section64] { base.sections64 }
    package var sections32: [Section] { base.sections32 }
    package var symbols: AnyRandomAccessCollection<Symbol> { base.symbols }
    package var symbols64: Symbols64? { base.symbols64 }
    package var symbols32: Symbols? { base.symbols32 }
    package var indirectSymbols: IndirectSymbols? { base.indirectSymbols }
    package var symbolStrings: Strings? { base.symbolStrings }
    package var cStrings: Strings? { base.cStrings }
    package var allCStringTables: [Strings] { base.allCStringTables }
    package var allCStrings: [String] { base.allCStrings }
    package var uStrings: UTF16Strings? { base.uStrings }
    package var cfStrings: [any CFStringProtocol]? { base.cfStrings }
    package var cfStrings64: CFStrings64? { base.cfStrings64 }
    package var cfStrings32: CFStrings32? { base.cfStrings32 }
    package var embeddedInfoPlist: [String: Any]? { base.embeddedInfoPlist }
    package var rebaseOperations: RebaseOperations? { base.rebaseOperations }
    package var bindOperations: BindOperations? { base.bindOperations }
    package var weakBindOperations: BindOperations? { base.weakBindOperations }
    package var lazyBindOperations: BindOperations? { base.lazyBindOperations }
    package var exportTrie: ExportTrie? { base.exportTrie }
    package var exportedSymbols: [ExportedSymbol] { base.exportedSymbols }
    package var bindingSymbols: [BindingSymbol] { base.bindingSymbols }
    package var weakBindingSymbols: [BindingSymbol] { base.weakBindingSymbols }
    package var lazyBindingSymbols: [BindingSymbol] { base.lazyBindingSymbols }
    package var rebases: [Rebase] { base.rebases }
    package var functionStarts: FunctionStarts? { base.functionStarts }
    package var dataInCode: DataInCode? { base.dataInCode }
    package var dyldChainedFixups: DyldChainedFixups? { base.dyldChainedFixups }
    package var externalRelocations: ExternalRelocations? { base.externalRelocations }
    package var classicBindingSymbols: [ClassicBindingSymbol]? { base.classicBindingSymbols }
    package var classicLazyBindingSymbols: [ClassicBindingSymbol]? { base.classicLazyBindingSymbols }
    package var codeSign: CodeSign? { base.codeSign }
    package var expectedMachOFileSize: Int? { base.expectedMachOFileSize }

    package func closestSymbol(at offset: Int, inSection sectionNumber: Int, isGlobalOnly: Bool) -> Symbol? {
        base.closestSymbol(at: offset, inSection: sectionNumber, isGlobalOnly: isGlobalOnly)
    }

    package func closestSymbols(at offset: Int, inSection sectionNumber: Int, isGlobalOnly: Bool) -> [Symbol] {
        base.closestSymbols(at: offset, inSection: sectionNumber, isGlobalOnly: isGlobalOnly)
    }

    package func symbol(for offset: Int, inSection sectionNumber: Int, isGlobalOnly: Bool) -> Symbol? {
        base.symbol(for: offset, inSection: sectionNumber, isGlobalOnly: isGlobalOnly)
    }

    package func symbols(for offset: Int, inSection sectionNumber: Int, isGlobalOnly: Bool) -> [Symbol] {
        base.symbols(for: offset, inSection: sectionNumber, isGlobalOnly: isGlobalOnly)
    }

    package func symbols(named name: String, mangled: Bool) -> [Symbol] {
        base.symbols(named: name, mangled: mangled)
    }

    package func symbol(named name: String, mangled: Bool, inSection sectionNumber: Int, isGlobalOnly: Bool) -> Symbol? {
        base.symbol(named: name, mangled: mangled, inSection: sectionNumber, isGlobalOnly: isGlobalOnly)
    }

    package func contains(unslidAddress address: UInt64) -> Bool {
        base.contains(unslidAddress: address)
    }

    package func stripPointerTags(of rawVMAddr: UInt64) -> UInt64 {
        base.stripPointerTags(of: rawVMAddr)
    }
}

// MARK: - MachORepresentableWithCache

extension ForwardingMachOReader {
    package typealias Cache = Base.Cache
    package typealias Identifier = Base.Identifier

    package var imagePath: String { base.imagePath }
    package var identifier: Identifier { base.identifier }
    package var cache: Cache? { base.cache }
    package var startOffset: Int { base.startOffset }

    package func resolveOffset(at address: UInt64) -> Int {
        base.resolveOffset(at: address)
    }
}

// MARK: - Readable

extension ForwardingMachOReader {
    package func readElement<Element>(offset: Int) throws -> Element {
        try base.readElement(offset: offset)
    }

    package func readElement<Element>(offset: Int) throws -> Element where Element: LocatableLayoutWrapper {
        try base.readWrapperElement(offset: offset)
    }

    package func readWrapperElement<Element>(offset: Int) throws -> Element where Element: LocatableLayoutWrapper {
        try base.readWrapperElement(offset: offset)
    }

    package func readElements<Element>(offset: Int, numberOfElements: Int) throws -> [Element] {
        try base.readElements(offset: offset, numberOfElements: numberOfElements)
    }

    package func readElements<Element>(offset: Int, numberOfElements: Int) throws -> [Element] where Element: LocatableLayoutWrapper {
        try base.readWrapperElements(offset: offset, numberOfElements: numberOfElements)
    }

    package func readWrapperElements<Element>(offset: Int, numberOfElements: Int) throws -> [Element] where Element: LocatableLayoutWrapper {
        try base.readWrapperElements(offset: offset, numberOfElements: numberOfElements)
    }

    package func readString(offset: Int) throws -> String {
        try base.readString(offset: offset)
    }
}

// MARK: - MachOSwiftSectionRepresentableWithCache

extension ForwardingMachOReader {
    package typealias SwiftSection = Base.SwiftSection

    package var swift: SwiftSection { base.swift }
}
