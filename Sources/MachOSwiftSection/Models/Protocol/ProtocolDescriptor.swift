import Foundation
import MachOKit

public struct ProtocolDescriptor: LayoutWrapperWithOffset {
    public struct Layout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeOffset
        public var name: RelativeDirectPointer<String>
        public var numRequirementsInSignature: UInt32
        public var numRequirements: UInt32
        public var associatedTypes: RelativeDirectPointer<String>
    }
    
    public var offset: Int
    public var layout: Layout

    
    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
    
    public func offset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        return offset + layoutOffset(of: keyPath)
    }
}

extension ProtocolDescriptor {
    public func name(in machO: MachOFile) throws -> String {
        try layout.name.resolve(from: offset(of: \.name).cast(), in: machO)
    }
}
