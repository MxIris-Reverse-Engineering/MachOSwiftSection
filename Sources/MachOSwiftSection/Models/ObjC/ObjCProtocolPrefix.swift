import Foundation
import MachOKit

public struct ObjCProtocolPrefix: LocatableLayoutWrapper {
    public struct Layout {
        public let isa: UInt64
        public let name: Pointer<MangledName>
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension ObjCProtocolPrefix {
    public func name(in machOFile: MachOFile) throws -> MangledName {
        try layout.name.resolve(in: machOFile)
    }
}
