import SwiftDeclaration
@_spi(Internals) import MachOSymbols

/// Maps `SymbolIndexStore`'s symbol-derived type kind onto the declaration
/// model's `TypeKind`. Lives in `SwiftIndexing` rather than the base model
/// because `SymbolIndexStore.TypeInfo.Kind` is an `@_spi(Internals)` type and
/// this mapping is purely a symbol-index reading concern used by the indexer.
extension SymbolIndexStore.TypeInfo.Kind {
    var typeKind: TypeKind? {
        switch self {
        case .enum:
            .enum
        case .struct:
            .struct
        case .class:
            .class
        default:
            nil
        }
    }
}
