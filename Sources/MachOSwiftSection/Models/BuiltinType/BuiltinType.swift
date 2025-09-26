import Foundation
import MachOSymbols
import MachOKit
import MachOMacro
import MachOFoundation

public struct BuiltinType: TopLevelType {
    public let descriptor: BuiltinTypeDescriptor

    public let typeName: MangledName?

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(descriptor: BuiltinTypeDescriptor, in machO: MachO) throws {
        self.descriptor = descriptor
        self.typeName = try descriptor.typeName(in: machO)
    }
}


