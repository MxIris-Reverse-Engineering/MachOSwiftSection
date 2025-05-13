import Foundation
import MachOKit

public struct RelativeObjCProtocolPrefix: LocatableLayoutWrapper {
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

extension RelativeObjCProtocolPrefix {
    func mangledName(in machOFile: MachOFile) throws -> MangledName {
//        return try machOFile.readSymbolicMangledName(at: layout.mangledName.resolveDirectFileOffset(from: offset(of: \.mangledName)).cast())
        return try layout.mangledName.resolve(from: offset(of: \.mangledName), in: machOFile)
    }
}

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
    func name(in machOFile: MachOFile) throws -> MangledName {
        try layout.name.resolve(in: machOFile)
    }
}
