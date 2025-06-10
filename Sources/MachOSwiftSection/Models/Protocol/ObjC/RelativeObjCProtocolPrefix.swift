import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

public struct RelativeObjCProtocolPrefix: ResolvableLocatableLayoutWrapper {
    public struct Layout: Sendable {
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

@MachOImageAllMembersGenerator
extension RelativeObjCProtocolPrefix {
    func mangledName(in machOFile: MachOFile) throws -> MangledName {
        return try layout.mangledName.resolve(from: offset(of: \.mangledName), in: machOFile)
    }
}


