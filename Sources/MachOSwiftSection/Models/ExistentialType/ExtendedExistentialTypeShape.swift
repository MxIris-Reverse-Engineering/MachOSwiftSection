import Foundation
import MachOKit

public struct ExtendedExistentialTypeShape: LocatableLayoutWrapper, ResolvableElement {
    public struct Layout {
        public let flags: ExtendedExistentialTypeShapeFlags
        public let existentialType: RelativeDirectPointer<MangledName>
        public let requirementSignatureHeader: GenericContextDescriptorHeader.Layout
    }
    
    public let offset: Int
    
    public var layout: Layout
    
    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension ExtendedExistentialTypeShape {
    public func existentialType(in machO: MachOFile) throws -> MangledName {
        try layout.existentialType.resolve(from: offset(of: \.existentialType), in: machO)
    }
}

public struct ExtendedExistentialTypeShapeFlags: OptionSet {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}
