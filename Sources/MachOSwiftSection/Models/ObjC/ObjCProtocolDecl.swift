import Foundation
import MachOKit

public struct ObjCProtocolDecl: LayoutWrapperWithOffset {
    public struct Layout {
        public let unknown: Int32
        public let mangledName: RelativeDirectPointer<String>
    }
    
    public let offset: Int
    
    public var layout: Layout
    
    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}


extension ObjCProtocolDecl {
    func mangledName(in machOFile: MachOFile) throws -> String {
        return try machOFile.readSymbolicMangledName(at: try layout.mangledName.resolveFileOffset(from: offset(of: \.mangledName), in: machOFile).cast())
    }
}
