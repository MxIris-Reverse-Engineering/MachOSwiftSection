import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

public struct ObjCProtocolPrefix: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
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

extension ObjCProtocolPrefix {
    public func name<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> String {
        try layout.name.resolve(in: machO)
    }
    
    public func mangledName<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> MangledName {
        try Pointer<MangledName>(address: layout.name.address).resolve(in: machO)
    }
}
