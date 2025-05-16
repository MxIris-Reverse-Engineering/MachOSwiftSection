import Foundation
import MachOKit

public struct RelativeObjCProtocolPrefix: LocatableLayoutWrapper {
    public struct Layout {
        public let isa: RelativeDirectRawPointer
        public let mangledName: RelativeDirectPointer<MangledName>
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension RelativeObjCProtocolPrefix {
    func mangledName(in machOFile: MachOFile) throws -> MangledName {
        return try layout.mangledName.resolve(from: fileOffset(of: \.mangledName), in: machOFile)
    }
}


