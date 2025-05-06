import Foundation
import MachOKit

public struct ObjCProtocolPrefix: LocatableLayoutWrapper {
    public struct Layout {
        public let isa: RelativeOffset
        public let mangledName: RelativeDirectPointer<String>
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension ObjCProtocolPrefix {
    func mangledName(in machOFile: MachOFile) throws -> String {
        return try machOFile.readSymbolicMangledName(at: layout.mangledName.resolveDirectFileOffset(from: offset(of: \.mangledName)).cast())
    }
}
