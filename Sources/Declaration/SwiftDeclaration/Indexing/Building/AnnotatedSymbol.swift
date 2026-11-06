import MemberwiseInit
@_spi(Internals) import MachOSymbols

/// A `DemangledSymbol` carried through the build path together with one extra
/// value whose meaning belongs to the path, not to the symbol itself.
///
/// Read the payload through the semantic accessor a specialization declares —
/// `protocolWitnessTableOffset` below — rather than through `payload`: the
/// stored name says only THAT there is an extra value, the semantic one says
/// WHICH.
///
/// The `@dynamicMemberLookup` forwarding is what lets the builders read
/// `memberSymbol.demangledNode` without unwrapping `base` at every use. Note it
/// forwards `offset` too — the symbol's own byte offset in the image — so no
/// specialization may name its accessor `offset`: a member of that name shadows
/// the forwarded one silently, and the two mean entirely different things.
/// `AnnotatedSymbolTests.annotationDoesNotShadowTheForwardedSymbolOffset` pins
/// that.
@MemberwiseInit()
@dynamicMemberLookup
package struct AnnotatedSymbol<Payload> {
    package let base: DemangledSymbol
    package let payload: Payload

    package subscript<Value>(dynamicMember keyPath: KeyPath<DemangledSymbol, Value>) -> Value {
        base[keyPath: keyPath]
    }
}

extension AnnotatedSymbol: Sendable where Payload: Sendable {}

extension AnnotatedSymbol where Payload: ExpressibleByNilLiteral {
    package init(_ base: DemangledSymbol) {
        self.init(base: base, payload: nil)
    }
}

extension Sequence<DemangledSymbol> {
    /// Wraps each symbol with no payload, for the producers that have none.
    package func mapToAnnotatedSymbols<Payload: ExpressibleByNilLiteral>() -> [AnnotatedSymbol<Payload>] {
        map { .init($0) }
    }
}

/// The byte offset of a slot in a protocol witness table.
///
/// A type tag, not a value type with behavior: it exists so the specialization
/// below can constrain on it instead of on a bare `Int?`, which any other
/// payload would match too. Producers and consumers both speak `RawValue`.
package struct ProtocolWitnessTableOffset: RawRepresentable, Sendable {
    package typealias RawValue = Int

    package let rawValue: RawValue

    package init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    package init(_ rawValue: RawValue) {
        self.rawValue = rawValue
    }
}

/// The protocol-side specialization: `ProtocolDefinition.index(in:)` walks
/// requirements in witness-table order and annotates each symbol with the byte
/// offset of the slot it occupies. Every other producer leaves it `nil`.
extension AnnotatedSymbol where Payload == ProtocolWitnessTableOffset? {
    package var protocolWitnessTableOffset: ProtocolWitnessTableOffset.RawValue? {
        payload?.rawValue
    }

    package init(base: DemangledSymbol, protocolWitnessTableOffset: ProtocolWitnessTableOffset.RawValue?) {
        self.init(base: base, payload: protocolWitnessTableOffset.map(ProtocolWitnessTableOffset.init(_:)))
    }
}

/// What every `DefinitionBuilder` entry point consumes: a symbol plus the
/// witness-table slot it occupies, if its producer knew one.
package typealias MemberSymbol = AnnotatedSymbol<ProtocolWitnessTableOffset?>
