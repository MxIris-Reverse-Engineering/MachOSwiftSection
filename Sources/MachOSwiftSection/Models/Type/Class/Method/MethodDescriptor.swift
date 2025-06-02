import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

public struct MethodDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout {
        public let flags: MethodDescriptorFlags
        public let implementation: RelativeDirectPointer<MachOSymbol?>
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

@MachOImageAllMembersGenerator
extension MethodDescriptor {
    //@MachOImageGenerator
    public func implementationSymbol(in machOFile: MachOFile) throws -> MachOSymbol? {
        return try layout.implementation.resolve(from: offset(of: \.implementation), in: machOFile)
    }
}
