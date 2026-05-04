import Foundation
import MachOKit
import MachOFoundation

public struct ExtensionContext: TopLevelType, ContextProtocol {
    public let descriptor: ExtensionContextDescriptor

    public let genericContext: GenericContext?

    public let extendedContextMangledName: MangledName?

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(descriptor: ExtensionContextDescriptor, in machO: MachO) throws {
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
    public init<Context: ReadingContext>(descriptor: ExtensionContextDescriptor, in context: Context) throws {
        self.descriptor = descriptor
        self.extendedContextMangledName = try descriptor.extendedContext(in: context)
        self.genericContext = try descriptor.genericContext(in: context)
    }
}
