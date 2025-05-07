import Foundation
import MachOKit

public struct ObjCProtocolPrefix: LocatableLayoutWrapper {
    public struct Layout {
        public let isa: RelativeOffset
        public let mangledName: RelativeDirectPointer<MangledName>
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension ObjCProtocolPrefix {
    func mangledName(in machOFile: MachOFile) throws -> MangledName {
//        return try machOFile.readSymbolicMangledName(at: layout.mangledName.resolveDirectFileOffset(from: offset(of: \.mangledName)).cast())
        return try layout.mangledName.resolve(from: offset(of: \.mangledName), in: machOFile)
    }
}
