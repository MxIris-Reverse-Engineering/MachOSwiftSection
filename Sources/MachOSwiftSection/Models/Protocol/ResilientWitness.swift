import Foundation
import MachOKit
import MachOFoundation

public struct ResilientWitness: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let requirement: RelativeProtocolRequirementPointer
        public let implementation: RelativeDirectPointer<Symbols?>
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

    public var implementationOffset: Int {
        layout.implementation.resolveDirectOffset(from: offset(of: \.implementation))
    }
    
    /// MachO-only debug formatter; no `ReadingContext` mirror exists because
    /// `addressString(forOffset:)` is a MachO display helper (not a data read)
    /// and has no counterpart on the unified `ReadingContext` abstraction.
    public func implementationAddress(in machO: some MachOSwiftSectionRepresentableWithCache) -> String {
        return machO.addressString(forOffset: implementationOffset)
    }
    
    public func implementationSymbols<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> Symbols? {
        return try layout.implementation.resolve(from: offset(of: \.implementation), in: machO)
    }
}

// MARK: - ReadingContext Support

extension ResilientWitness {
    public func requirement<Context: ReadingContext>(in context: Context) throws -> SymbolOrElement<ProtocolRequirement>? {
        return try layout.requirement.resolve(at: try context.addressFromOffset(offset(of: \.requirement)), in: context).asOptional
    }

    public func implementationSymbols<Context: ReadingContext>(in context: Context) throws -> Symbols? {
        return try layout.implementation.resolve(at: try context.addressFromOffset(offset(of: \.implementation)), in: context)
    }
}
