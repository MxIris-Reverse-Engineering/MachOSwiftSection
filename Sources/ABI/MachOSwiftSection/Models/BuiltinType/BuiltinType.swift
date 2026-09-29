import Foundation
import MachOKit
import MachOBase

public struct BuiltinType: TopLevelType {
    public let descriptor: BuiltinTypeDescriptor

    public let typeName: MangledName?

    public init(descriptor: BuiltinTypeDescriptor, in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        self.descriptor = descriptor
        self.typeName = try descriptor.typeName(in: machO)
    }
    
    public init(descriptor: BuiltinTypeDescriptor) throws {
        self.descriptor = descriptor
        self.typeName = try descriptor.typeName()
    }
}

// MARK: - ReadingContext Support

extension BuiltinType {
    public init(descriptor: BuiltinTypeDescriptor, in context: some ReadingContext) throws {
        self.descriptor = descriptor
        self.typeName = try descriptor.typeName(in: context)
    }
}
