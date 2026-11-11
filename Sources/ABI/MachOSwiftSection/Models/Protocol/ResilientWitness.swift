import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct ResilientWitness {
    public struct Layout: LayoutProtocol {
        public let requirement: RelativeProtocolRequirementPointer
        public let implementation: RelativeDirectRawPointer
    }
}

extension ResilientWitness {
    /// File offset of the witness implementation, or `nil` for a null
    /// pointer. Pure pointer arithmetic on the descriptor's own offset;
    /// symbol attribution is `SwiftInspection`'s `implementationSymbols(in:)`,
    /// one layer up.
    public var implementationOffset: Int? {
        resolvedDirectOffset(from: \.implementation)
    }

    /// The witness implementation's address formatted for display (`nil` for
    /// a null pointer). A Mach-O display helper rather than a data read, so it
    /// takes the Mach-O itself; ``implementationAddress(in:)`` answers the
    /// typed address in a `ReadingContext` instead.
    public func implementationAddressString(in machO: some MachOSwiftSectionRepresentableWithCache) -> String? {
        return implementationOffset.map { machO.addressString(forOffset: $0) }
    }
}

// MARK: - ReadingContext Support

extension ResilientWitness {
    public func requirement(in context: some ReadingContext) throws -> SymbolOrElement<ProtocolRequirement>? {
        return try layout.requirement.resolve(at: try context.addressFromOffset(offset(of: \.requirement)), in: context).asOptional
    }

    /// The witness implementation's location as an address in `context`, or
    /// `nil` for a null pointer.
    public func implementationAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address? {
        guard let implementationOffset else { return nil }
        return try context.addressFromOffset(implementationOffset)
    }
}
