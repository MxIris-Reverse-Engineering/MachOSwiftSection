import Foundation
import MachOKit

public struct ExtensionContext {
    public let descriptor: ExtensionContextDescriptor

    public let genericContext: GenericContext?

    public let extendedContextMangledName: MangledName?

    public init(descriptor: ExtensionContextDescriptor, in machOFile: MachOFile) throws {
        self.descriptor = descriptor
        self.extendedContextMangledName = try descriptor.extendedContext(in: machOFile)
        self.genericContext = try descriptor.genericContext(in: machOFile)
    }
}
