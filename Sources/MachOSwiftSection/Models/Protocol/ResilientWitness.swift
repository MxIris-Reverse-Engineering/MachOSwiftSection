import Foundation
import MachOKit
import MachOBase

public struct ResilientWitness: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let requirement: RelativeProtocolRequirementPointer
        public let implementation: RelativeDirectRawPointer
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension ResilientWitness {
    public func requirement<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> SymbolOrElement<ProtocolRequirement>? {
        return try layout.requirement.resolve(from: offset(of: \.requirement), in: machO).asOptional
    }
    
    public func requirement() throws -> SymbolOrElement<ProtocolRequirement>? {
        return try layout.requirement.resolve(from: pointer(of: \.requirement)).asOptional
    }

    /// File offset of the witness implementation, or `nil` for a null
    /// pointer. Pure pointer arithmetic on the descriptor's own offset;
    /// symbol attribution is `SwiftInspection`'s `implementationSymbols(in:)`,
    /// one layer up.
    public var implementationOffset: Int? {
        guard layout.implementation.isValid else { return nil }
        return layout.implementation.resolveDirectOffset(from: offset(of: \.implementation))
    }

    /// MachO-only debug formatter (`nil` for a null pointer); no
    /// `ReadingContext` mirror exists because `addressString(forOffset:)` is a
    /// MachO display helper (not a data read) and has no counterpart on the
    /// unified `ReadingContext` abstraction — the context-flavored
    /// ``implementationAddress(in:)-swift.method`` below returns the typed
    /// address instead.
    public func implementationAddress(in machO: some MachOSwiftSectionRepresentableWithCache) -> String? {
        return implementationOffset.map { machO.addressString(forOffset: $0) }
    }
}

// MARK: - ReadingContext Support

extension ResilientWitness {
    public func requirement<Context: ReadingContext>(in context: Context) throws -> SymbolOrElement<ProtocolRequirement>? {
        return try layout.requirement.resolve(at: try context.addressFromOffset(offset(of: \.requirement)), in: context).asOptional
    }

    /// The witness implementation's location as an address in `context`, or
    /// `nil` for a null pointer.
    public func implementationAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address? {
        guard let implementationOffset else { return nil }
        return try context.addressFromOffset(implementationOffset)
    }
}
