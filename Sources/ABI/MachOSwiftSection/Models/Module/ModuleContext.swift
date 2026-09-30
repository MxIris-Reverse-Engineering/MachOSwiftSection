import Foundation
import MachOKit
import MachOBase

public struct ModuleContext: TopLevelType, ContextProtocol {
    public let descriptor: ModuleContextDescriptor

    public let name: String
}

// MARK: - ReadingContext Support

extension ModuleContext {
    public init(descriptor: ModuleContextDescriptor, in context: some ReadingContext) throws {
        self.descriptor = descriptor
        self.name = try descriptor.name(in: context)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension ModuleContext {
    @available(*, deprecated, message: "Pass a ReadingContext: ModuleContext(descriptor:in: machO.context).")
    public init(descriptor: ModuleContextDescriptor, in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        try self.init(descriptor: descriptor, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: ModuleContext(descriptor:in: .inProcess).")
    public init(descriptor: ModuleContextDescriptor) throws {
        try self.init(descriptor: descriptor, in: InProcessContext.shared)
    }
}
