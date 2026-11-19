@_spi(Internals) import MachOSymbols

/// How `SwiftSymbolIndexStore` routes an image's names through
/// MachOKitExtensions' `SymbolSweep`: Swift-mangled names into the table it
/// demangles and indexes by offset, the names the Swift compiler emits for
/// the linker to de-duplicate (`_symbolic `, `_default assoc type `) into a
/// table of their own that no offset or name query sees, and every other
/// name nowhere.
struct SwiftSymbolTableRouting: SymbolTableRouting {
    enum Table: Hashable, Sendable {
        /// Swift-mangled names: demangled into the index, found by offset.
        case swift
        /// `_symbolic ` / `_default assoc type ` names, which never demangle:
        /// read only by `SymbolicManglingIndex`, by name.
        case symbolicMangling
    }

    func table(forSymbolNamed name: UnsafePointer<CChar>, language: SymbolLanguage) -> Table? {
        guard language == .swift else { return nil }
        return nameBytesHaveSymbolicManglingSymbolPrefix(name) ? .symbolicMangling : .swift
    }

    func offsetIndexing(in table: Table) -> SymbolOffsetIndexing {
        switch table {
        case .swift:
            .byOffset
        case .symbolicMangling:
            .nameOnly
        }
    }

    /// dyld pins every image carrying Swift content as never-unload, so a
    /// loaded image's Swift names can stay in its string table.
    var mayReferenceStringTablesOfLoadedImages: Bool {
        true
    }
}
