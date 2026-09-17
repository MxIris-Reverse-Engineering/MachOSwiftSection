import MemberwiseInit
@_spi(Internals) import MachOSymbols

/// A demangled symbol carried through the build path together with the byte
/// offset it occupies in its container's protocol witness table.
///
/// Only the protocol-side producers (`ProtocolDefinition.index(in:)`, which
/// walks requirements in witness-table order) have an offset to supply; the
/// nominal-type path passes `nil` and the built member's `offset` stays empty.
/// The `@dynamicMemberLookup` forwarding is what lets the builders read
/// `demangledSymbol.demangledNode` without unwrapping `base` at every use.
@MemberwiseInit()
@dynamicMemberLookup
package struct DemangledSymbolWithOffset {
    package let base: DemangledSymbol
    package let offset: Int?

    package init(_ base: DemangledSymbol) {
        self.base = base
        self.offset = nil
    }

    package subscript<Value>(dynamicMember keyPath: KeyPath<DemangledSymbol, Value>) -> Value {
        base[keyPath: keyPath]
    }
}

extension Sequence<DemangledSymbol> {
    package func mapToDemangledSymbolWithOffset() -> [DemangledSymbolWithOffset] {
        map { .init($0) }
    }
}
