import Foundation
import MachOKit
import MachOFoundation
import MachOMacro

public struct ExtendedExistentialTypeShape: ResolvableLocatableLayoutWrapper {
    public struct Layout: Sendable {
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
    public func existentialType<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> MangledName {
        try layout.existentialType.resolve(from: offset(of: \.existentialType), in: machO)
    }
}

public struct ExtendedExistentialTypeShapeFlags: OptionSet, Sendable {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}
