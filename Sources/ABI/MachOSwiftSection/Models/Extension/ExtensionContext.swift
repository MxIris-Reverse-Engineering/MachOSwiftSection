import Foundation
import MachOKit
import MachOBase

public struct ExtensionContext: TopLevelType, ContextProtocol {
    public let descriptor: ExtensionContextDescriptor

    public let genericContext: GenericContext?

    public let extendedContextMangledName: MangledName?
}

// MARK: - ReadingContext Support

extension ExtensionContext {
    public init(descriptor: ExtensionContextDescriptor, in context: some ReadingContext) throws {
        self.descriptor = descriptor
        self.extendedContextMangledName = try descriptor.extendedContext(in: context)
        self.genericContext = try descriptor.genericContext(in: context)
    }
}
