import MachOKit
import MachOFoundation
import MachOSwiftSection

// Symbol attribution for the ABI layer's implementation pointers.
//
// `MachOSwiftSection` only knows an implementation's *offset*
// (`implementationOffset`); which symbol names sit at that offset is a
// symbol-index question, answered here where `MachOSymbols` is in reach
// (evolution proposal `self-contained-abi-layer`). Several names can share
// one offset under identical code folding, hence `Symbols`, not `Symbol`.
// Only the MachO-backed form exists: a `ReadingContext` carries no symbol
// service to consult.

extension MethodDescriptor {
    /// The symbols the image's index finds at the implementation's offset;
    /// `nil` when the descriptor has no implementation or the index knows
    /// nothing at that offset.
    public func implementationSymbols<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) -> Symbols? {
        guard let implementationOffset else { return nil }
        return machO.symbols(offset: implementationOffset)
    }
}

extension MethodOverrideDescriptor {
    /// The symbols the image's index finds at the overriding implementation's
    /// offset; `nil` for a null pointer or an offset the index does not know.
    public func implementationSymbols<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) -> Symbols? {
        guard let implementationOffset else { return nil }
        return machO.symbols(offset: implementationOffset)
    }
}

extension MethodDefaultOverrideDescriptor {
    /// The symbols the image's index finds at the default-override
    /// implementation's offset; `nil` for a null pointer or an offset the
    /// index does not know.
    public func implementationSymbols<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) -> Symbols? {
        guard let implementationOffset else { return nil }
        return machO.symbols(offset: implementationOffset)
    }
}

extension ProtocolRequirement {
    /// The symbols the image's index finds at the requirement's default
    /// implementation; `nil` when the requirement has none or the index does
    /// not know the offset.
    public func defaultImplementationSymbols<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) -> Symbols? {
        guard let defaultImplementationOffset else { return nil }
        return machO.symbols(offset: defaultImplementationOffset)
    }
}

extension ResilientWitness {
    /// The symbols the image's index finds at the witness implementation's
    /// offset; `nil` for a null pointer or an offset the index does not know.
    public func implementationSymbols<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) -> Symbols? {
        guard let implementationOffset else { return nil }
        return machO.symbols(offset: implementationOffset)
    }
}
