import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

public struct ExtensionContext: TopLevelType, ContextProtocol {
    public let descriptor: ExtensionContextDescriptor

    public let genericContext: GenericContext?

    public let extendedContextMangledName: MangledName?

    public init<MachO: MachORepresentableWithCache & MachOReadable>(descriptor: ExtensionContextDescriptor, in machO: MachO) throws {
        self.descriptor = descriptor
        self.extendedContextMangledName = try descriptor.extendedContext(in: machO)
        self.genericContext = try descriptor.genericContext(in: machO)
    }
}
