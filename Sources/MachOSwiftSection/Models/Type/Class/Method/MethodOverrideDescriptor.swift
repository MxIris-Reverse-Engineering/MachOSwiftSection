import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

public struct MethodOverrideDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: Sendable {
        public let `class`: RelativeContextPointer
        public let method: RelativeMethodDescriptorPointer
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
extension MethodOverrideDescriptor {
    
    public func methodDescriptor(in machOFile: MachOFile) throws -> SymbolOrElement<MethodDescriptor>? {
        return try layout.method.resolve(from: offset(of: \.method), in: machOFile).asOptional
    }
    
    public func implementationSymbol(in machOFile: MachOFile) throws -> MachOSymbol? {
        return try layout.implementation.resolve(from: offset(of: \.implementation), in: machOFile)
    }
}
