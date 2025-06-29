import Foundation
import MachOSymbols
import MachOKit
import MachOMacro

public struct BuiltinType: TopLevelType {
    public let descriptor: BuiltinTypeDescriptor

    public let typeName: MangledName?

    @MachOImageGenerator
    public init(descriptor: BuiltinTypeDescriptor, in machO: MachOFile) throws {
        self.descriptor = descriptor
        self.typeName = try descriptor.typeName(in: machO)
    }
}


