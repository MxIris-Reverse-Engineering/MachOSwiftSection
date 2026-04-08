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
    
    public func implementationAddress(in machO: some MachOSwiftSectionRepresentableWithCache) -> String {
        return machO.addressString(forOffset: implementationOffset)
    }
    
    public func implementationSymbols<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> Symbols? {
        return try layout.implementation.resolve(from: offset(of: \.implementation), in: machO)
    }
}
