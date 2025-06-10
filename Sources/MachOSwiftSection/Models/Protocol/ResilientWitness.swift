import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

public struct ResilientWitness: ResolvableLocatableLayoutWrapper {
    public struct Layout: Sendable {
        public let requirement: RelativeProtocolRequirementPointer
        public let implementation: RelativeDirectPointer<MachOSymbol?>
    }
    
    public let offset: Int
    
    public var layout: Layout
    
    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}


@MachOImageAllMembersGenerator
extension ResilientWitness {
    public func requirement(in machOFile: MachOFile) throws -> SymbolOrElement<ProtocolRequirement>? {
        return try layout.requirement.resolve(from: offset(of: \.requirement), in: machOFile).asOptional
    }
    
    public func implementationSymbol(in machOFile: MachOFile) throws -> MachOSymbol? {
        return try layout.implementation.resolve(from: offset(of: \.implementation), in: machOFile)
    }
}
