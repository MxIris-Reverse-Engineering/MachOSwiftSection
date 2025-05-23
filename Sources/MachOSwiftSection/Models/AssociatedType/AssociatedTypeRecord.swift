import Foundation
import MachOKit

public struct AssociatedTypeRecord: LocatableLayoutWrapper {
    public struct Layout {
        public let name: RelativeDirectPointer<String>
        public let substitutedTypeName: RelativeDirectPointer<MangledName>
    }
    
    public var layout: Layout
    
    public var offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

extension AssociatedTypeRecord {
    public func name(in machOFile: MachOFile) throws -> String {
        return try layout.name.resolve(from: fileOffset(of: \.name), in: machOFile)
    }
    
    public func substitutedTypeName(in machOFile: MachOFile) throws -> MangledName {
        return try layout.substitutedTypeName.resolve(from: fileOffset(of: \.substitutedTypeName), in: machOFile)
    }
}
