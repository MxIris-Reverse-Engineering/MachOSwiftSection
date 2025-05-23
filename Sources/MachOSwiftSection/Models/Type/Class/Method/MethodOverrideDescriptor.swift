import Foundation
import MachOKit

public struct MethodOverrideDescriptor: LocatableLayoutWrapper {
    public struct Layout {
        public let `class`: RelativeContextPointer<ContextDescriptorWrapper?>
        public let method: RelativeMethodDescriptorPointer
        public let implementation: RelativeDirectPointer<UnsolvedSymbol?>
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

extension MethodOverrideDescriptor {
    public func implementationSymbol(in machOFile: MachOFile) throws -> UnsolvedSymbol? {
        return try layout.implementation.resolve(from: fileOffset(of: \.implementation), in: machOFile)
    }
}
