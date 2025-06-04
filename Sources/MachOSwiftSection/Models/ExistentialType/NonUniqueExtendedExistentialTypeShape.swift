import Foundation
import MachOKit
import MachOFoundation
import MachOMacro

public struct NonUniqueExtendedExistentialTypeShape: ResolvableLocatableLayoutWrapper {
    public struct Layout: Sendable {
        public let uniqueCache: RelativeDirectPointer<Pointer<ExtendedExistentialTypeShape>>
        public let localCopy: ExtendedExistentialTypeShape.Layout
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

extension NonUniqueExtendedExistentialTypeShape {
    @MachOImageGenerator
    public func existentialType(in machOFile: MachOFile) throws -> MangledName {
        try layout.localCopy.existentialType.resolve(from: offset(of: \.localCopy.existentialType), in: machOFile)
    }
}
