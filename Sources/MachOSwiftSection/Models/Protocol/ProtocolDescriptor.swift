import Foundation
@_spi(Support) import MachOKit

public struct ProtocolDescriptor: LayoutWrapperWithOffset {
    public struct Layout {
        public let context: ContextDescriptor.Layout
        public var name: RelativeDirectPointer
        public var numRequirementsInSignature: UInt32
        public var numRequirements: UInt32
        public var associatedTypes: RelativeDirectPointer
    }
    
    public var layout: Layout
    public var offset: Int

    @_spi(Core)
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }

    
    public func offset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        return offset + layoutOffset(of: keyPath)
    }
}

extension ProtocolDescriptor {
    public func name(in machO: MachOFile) -> String {
        let address = offset(of: \.name) + Int(layout.name) + machO.headerStartOffset
        return machO.fileHandle.readString(offset: numericCast(address))!
    }
}
