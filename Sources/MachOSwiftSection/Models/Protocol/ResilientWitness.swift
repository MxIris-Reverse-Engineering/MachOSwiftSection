import Foundation
import MachOKit
import MachOMacro

public struct ResilientWitness: ResolvableLocatableLayoutWrapper {
    public struct Layout {
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
    @MachOImageGenerator
    public func requirement(in machOFile: MachOFile) throws -> ResolvableElement<ProtocolRequirement>? {
        return try layout.requirement.resolve(from: offset(of: \.requirement), in: machOFile).asOptional
    }
}
