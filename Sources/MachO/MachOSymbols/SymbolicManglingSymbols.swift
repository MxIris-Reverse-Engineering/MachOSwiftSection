import Foundation
import MachOResolving

/// The symbols an image's symbolic manglings are named by, as
/// `SymbolIndexStore`'s build sweep collected them (evolution proposal
/// `symbolic-mangling-symbol-index`).
///
/// Every mangled name the compiler emits into `__swift5_typeref` with
/// symbolic references in it also gets a symbol, whose name is the linker's
/// uniquing key for it (`IRGenMangler::mangleSymbolNameForSymbolicMangling`):
/// a role prefix, the mangled name with each five-byte symbolic reference
/// spelled `_____`, then one space-separated referent per reference, in
/// reference order — the full mangling of what that reference points at. The
/// references themselves are relative offsets, so these names are the only
/// place a binary spells its referents out, private discriminators included.
///
/// Kept apart from the table `symbols(for:in:)` answers from: none of these
/// names demangle, and the callers of that query expect names that do.
/// Decoding the references needs the ABI model, which this module does not
/// see — that is SwiftInspection's `SymbolicManglingIndex`.
///
/// Row-indexed and zero-copy like the main table: a `MachOImage`'s names stay
/// in its mapped string table and are materialized on access.
package struct SymbolicManglingSymbols: RandomAccessCollection, Sendable {
    let symbolTable: SymbolTable

    init(symbolTable: SymbolTable) {
        self.symbolTable = symbolTable
    }

    package var startIndex: Int {
        0
    }

    package var endIndex: Int {
        symbolTable.rowCount
    }

    /// The symbol at `position`: its offset — where the mangled name it names
    /// starts, cache-adjusted like every other symbol offset — and its name.
    package subscript(position: Int) -> Symbol {
        symbolTable.symbol(atRow: UInt32(position))
    }

    /// The position of the symbol named exactly `name`.
    package func position(ofSymbolNamed name: String) -> Int? {
        symbolTable.row(forName: name).map { Int($0) }
    }
}

/// A symbolic-mangling symbol's name, split into its parts.
package struct SymbolicManglingSymbolName: Sendable {
    package enum Role: Sendable {
        /// `_symbolic ` — a type reference emitted for metadata, reflection or
        /// field metadata.
        case symbolic

        /// `_default assoc type ` — a default associated type witness. Its
        /// bytes open with a `0xFF` role marker, which the name spells as this
        /// prefix instead.
        case defaultAssociatedTypeWitness
    }

    package static let symbolicPrefix = "_symbolic "

    package static let defaultAssociatedTypeWitnessPrefix = "_default assoc type "

    package let role: Role

    /// The mangled name the symbol names, each symbolic reference spelled
    /// `_____`.
    package let mangledNameWithPlaceholders: Substring

    /// One mangling per symbolic reference, in the order the references occur
    /// in the mangled name — the only reliable way to pair them: the mangled
    /// name itself can put an underscore right next to a placeholder
    /// (`______pSgXw`, whose sixth belongs to `_p`).
    package let referentManglings: [Substring]

    /// `nil` for a name carrying neither prefix. A mangling never contains a
    /// space — an identifier with any character outside `[A-Za-z0-9_$]` is
    /// Punycode-encoded — so splitting the rest on spaces is exact.
    package init?(_ name: String) {
        let rest: Substring
        if name.hasPrefix(Self.symbolicPrefix) {
            role = .symbolic
            rest = name.dropFirst(Self.symbolicPrefix.count)
        } else if name.hasPrefix(Self.defaultAssociatedTypeWitnessPrefix) {
            role = .defaultAssociatedTypeWitness
            rest = name.dropFirst(Self.defaultAssociatedTypeWitnessPrefix.count)
        } else {
            return nil
        }
        let components = rest.split(separator: " ", omittingEmptySubsequences: false)
        mangledNameWithPlaceholders = components[0]
        referentManglings = Array(components.dropFirst())
    }

    /// Whether `name` is a symbolic-mangling symbol's, by prefix alone.
    package static func hasPrefix(_ name: String) -> Bool {
        name.hasPrefix(symbolicPrefix) || name.hasPrefix(defaultAssociatedTypeWitnessPrefix)
    }
}

/// Byte-level `SymbolicManglingSymbolName.hasPrefix(_:)` over a C string, so
/// the build sweep can pass over every other symbol without materializing its
/// name. Disjoint from `nameBytesHaveSwiftManglingPrefix`: neither prefix
/// starts like a Swift mangling. Pinned equal to the `String` check over a
/// real symbol table by `SymbolicManglingSymbolCollectionTests`.
func nameBytesHaveSymbolicManglingSymbolPrefix(_ nameC: UnsafePointer<CChar>) -> Bool {
    guard nameC.pointee == 0x5F else { return false } // "_"
    return strncmp(nameC, "_symbolic ", 10) == 0 || strncmp(nameC, "_default assoc type ", 20) == 0
}
