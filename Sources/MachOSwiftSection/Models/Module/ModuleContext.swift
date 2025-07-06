import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

public struct ModuleContext: TopLevelType, ContextProtocol {
    public let descriptor: ModuleContextDescriptor

    public let name: String

    public init<MachO: MachORepresentableWithCache & MachOReadable>(descriptor: ModuleContextDescriptor, in machO: MachO) throws {
        self.descriptor = descriptor
        self.name = try descriptor.name(in: machO)
    }
}
