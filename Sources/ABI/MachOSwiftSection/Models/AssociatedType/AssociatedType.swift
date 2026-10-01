import Foundation
import MachOKit
import MachOBase

public struct AssociatedType: TopLevelType {
    public let descriptor: AssociatedTypeDescriptor

    public let conformingTypeName: MangledName

    public let protocolTypeName: MangledName

    public let records: [AssociatedTypeRecord]
}

// MARK: - ReadingContext Support

extension AssociatedType {
    public init(descriptor: AssociatedTypeDescriptor, in context: some ReadingContext) throws {
        self.descriptor = descriptor
        self.conformingTypeName = try descriptor.conformingTypeName(in: context)
        self.protocolTypeName = try descriptor.protocolTypeName(in: context)
        self.records = try descriptor.associatedTypeRecords(in: context)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension AssociatedType {
    @available(*, deprecated, message: "Pass a ReadingContext: AssociatedType(descriptor:in: machO.context).")
    public init(descriptor: AssociatedTypeDescriptor, in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        try self.init(descriptor: descriptor, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: AssociatedType(descriptor:in: .inProcess).")
    public init(descriptor: AssociatedTypeDescriptor) throws {
        try self.init(descriptor: descriptor, in: InProcessContext.shared)
    }
}
