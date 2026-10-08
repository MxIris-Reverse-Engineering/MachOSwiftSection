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

// MARK: - Deprecated Mach-O and pointer forms

extension ExtensionContext {
    @available(*, deprecated, message: "Pass a ReadingContext: ExtensionContext(descriptor:in: machO.context).")
    public init(descriptor: ExtensionContextDescriptor, in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        try self.init(descriptor: descriptor, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: ExtensionContext(descriptor:in: .inProcess).")
    public init(descriptor: ExtensionContextDescriptor) throws {
        try self.init(descriptor: descriptor, in: InProcessContext.shared)
    }
}
