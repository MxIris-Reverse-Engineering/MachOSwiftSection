import Foundation
import MachOKit
import MachOBase

public struct AssociatedType: TopLevelType {
    public let descriptor: AssociatedTypeDescriptor

    public let conformingTypeName: MangledName

    public let protocolTypeName: MangledName

    public let records: [AssociatedTypeRecord]

    public init(descriptor: AssociatedTypeDescriptor, in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        self.descriptor = descriptor
        self.conformingTypeName = try descriptor.conformingTypeName(in: machO)
        self.protocolTypeName = try descriptor.protocolTypeName(in: machO)
        self.records = try descriptor.associatedTypeRecords(in: machO)
    }
    
    public init(descriptor: AssociatedTypeDescriptor) throws {
        self.descriptor = descriptor
        self.conformingTypeName = try descriptor.conformingTypeName()
        self.protocolTypeName = try descriptor.protocolTypeName()
        self.records = try descriptor.associatedTypeRecords()
    }
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
