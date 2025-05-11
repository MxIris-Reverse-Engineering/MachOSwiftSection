import Foundation
import MachOKit

public struct NonUniqueExtendedExistentialTypeShape: LocatableLayoutWrapper {
    public struct Layout {
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
    public func existentialType(in machO: MachOFile) throws -> MangledName {
        try layout.localCopy.existentialType.resolve(from: offset(of: \.localCopy.existentialType), in: machO)
    }
}
