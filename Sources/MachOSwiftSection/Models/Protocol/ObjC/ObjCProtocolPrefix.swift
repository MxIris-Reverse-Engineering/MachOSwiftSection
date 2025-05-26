import Foundation
import MachOKit
import MachOSwiftSectionMacro

public struct ObjCProtocolPrefix: LocatableLayoutWrapper {
    public struct Layout {
        public let isa: RawPointer
        public let name: Pointer<String>
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

@MachOImageAllMembersGenerator
extension ObjCProtocolPrefix {
    //@MachOImageGenerator
    public func name(in machOFile: MachOFile) throws -> String {
        try layout.name.resolve(in: machOFile)
    }
    
    //@MachOImageGenerator
    public func mangledName(in machOFile: MachOFile) throws -> MangledName {
        try Pointer<MangledName>(address: layout.name.address).resolve(in: machOFile)
    }
}
