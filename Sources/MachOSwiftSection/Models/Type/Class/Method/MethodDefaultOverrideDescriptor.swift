import Foundation
import MachOKit
import MachOSwiftSectionMacro

public struct MethodDefaultOverrideDescriptor: LocatableLayoutWrapper {
    public struct Layout {
        public let replacement: RelativeMethodDescriptorPointer
        public let original: RelativeMethodDescriptorPointer
        public let implementation: RelativeDirectPointer<UnsolvedSymbol?>
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

@MachOImageAllMembersGenerator
extension MethodDefaultOverrideDescriptor {
    //@MachOImageGenerator
    public func implementationSymbol(in machOFile: MachOFile) throws -> UnsolvedSymbol? {
        return try layout.implementation.resolve(from: offset(of: \.implementation), in: machOFile)
    }
}
