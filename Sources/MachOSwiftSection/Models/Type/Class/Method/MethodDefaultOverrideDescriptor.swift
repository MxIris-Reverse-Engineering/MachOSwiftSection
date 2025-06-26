import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

public struct MethodDefaultOverrideDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: Sendable {
        public let replacement: RelativeMethodDescriptorPointer
        public let original: RelativeMethodDescriptorPointer
        public let implementation: RelativeDirectPointer<Symbol?>
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
    public func implementationSymbol(in machOFile: MachOFile) throws -> Symbol? {
        return try layout.implementation.resolve(from: offset(of: \.implementation), in: machOFile)
    }
}
