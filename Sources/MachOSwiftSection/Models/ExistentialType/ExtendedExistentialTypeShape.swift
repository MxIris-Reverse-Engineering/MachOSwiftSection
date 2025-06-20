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
    @MachOImageGenerator
    public func existentialType(in machOFile: MachOFile) throws -> MangledName {
        try layout.existentialType.resolve(from: offset(of: \.existentialType), in: machOFile)
    }
}

public struct ExtendedExistentialTypeShapeFlags: OptionSet, Sendable {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}
