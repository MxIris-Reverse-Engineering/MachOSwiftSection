import Foundation
import MachOKit
import MachOBase

public struct ExtensionContext: TopLevelType, ContextProtocol {
    public let descriptor: ExtensionContextDescriptor

    public let genericContext: GenericContext?

    public let extendedContextMangledName: MangledName?

    public init(descriptor: ExtensionContextDescriptor, in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        self.descriptor = descriptor
        self.extendedContextMangledName = try descriptor.extendedContext(in: machO)
        self.genericContext = try descriptor.genericContext(in: machO)
    }
    
    public init(descriptor: ExtensionContextDescriptor) throws {
        self.descriptor = descriptor
        self.extendedContextMangledName = try descriptor.extendedContext()
        self.genericContext = try descriptor.genericContext()
    }
}

// MARK: - ReadingContext Support

extension ExtensionContext {
    public init(descriptor: ExtensionContextDescriptor, in context: some ReadingContext) throws {
        self.descriptor = descriptor
        self.extendedContextMangledName = try descriptor.extendedContext(in: context)
        self.genericContext = try descriptor.genericContext(in: context)
    }
}
