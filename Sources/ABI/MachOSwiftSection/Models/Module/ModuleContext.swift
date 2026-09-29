import Foundation
import MachOKit
import MachOBase

public struct ModuleContext: TopLevelType, ContextProtocol {
    public let descriptor: ModuleContextDescriptor

    public let name: String

    public init(descriptor: ModuleContextDescriptor, in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        self.descriptor = descriptor
        self.name = try descriptor.name(in: machO)
    }
    
    public init(descriptor: ModuleContextDescriptor) throws {
        self.descriptor = descriptor
        self.name = try descriptor.name()
    }
}

// MARK: - ReadingContext Support

extension ModuleContext {
    public init(descriptor: ModuleContextDescriptor, in context: some ReadingContext) throws {
        self.descriptor = descriptor
        self.name = try descriptor.name(in: context)
    }
}
