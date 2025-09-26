import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

public struct MethodDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let flags: MethodDescriptorFlags
        public let implementation: RelativeDirectPointer<Symbol?>
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

extension MethodDescriptor {
    public func implementationSymbol<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> Symbol? {
        return try layout.implementation.resolve(from: offset(of: \.implementation), in: machO)
    }
}
