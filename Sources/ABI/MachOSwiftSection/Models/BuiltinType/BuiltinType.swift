import Foundation
import MachOKit
import MachOBase

public struct BuiltinType: TopLevelType {
    public let descriptor: BuiltinTypeDescriptor

    public let typeName: MangledName?
}

// MARK: - ReadingContext Support

extension BuiltinType {
    public init(descriptor: BuiltinTypeDescriptor, in context: some ReadingContext) throws {
        self.descriptor = descriptor
        self.typeName = try descriptor.typeName(in: context)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension BuiltinType {
    @available(*, deprecated, message: "Pass a ReadingContext: BuiltinType(descriptor:in: machO.context).")
    public init(descriptor: BuiltinTypeDescriptor, in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        try self.init(descriptor: descriptor, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: BuiltinType(descriptor:in: .inProcess).")
    public init(descriptor: BuiltinTypeDescriptor) throws {
        try self.init(descriptor: descriptor, in: InProcessContext.shared)
    }
}
