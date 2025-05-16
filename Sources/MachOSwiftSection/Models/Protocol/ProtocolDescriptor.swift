import Foundation
import MachOKit

public struct ProtocolDescriptor: ProtocolDescriptorProtocol, Resolvable {
    public struct Layout: ProtocolDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeIndirectablePointer<ContextDescriptorWrapper?, SignedPointer<ContextDescriptorWrapper?>>
        public var name: RelativeDirectPointer<String>
        public var numRequirementsInSignature: UInt32
        public var numRequirements: UInt32
        public var associatedTypes: RelativeDirectPointer<String>
    }

    public var offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }

    public func offset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        return offset + layoutOffset(of: keyPath)
    }
}



