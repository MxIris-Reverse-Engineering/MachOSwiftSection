import Foundation
import MachOKit
import MachOMacro

public struct AssociatedType {
    public let descriptor: AssociatedTypeDescriptor

    public let conformingTypeName: MangledName

    public let protocolTypeName: MangledName

    public let records: [AssociatedTypeRecord]

    @MachOImageGenerator
    public init(descriptor: AssociatedTypeDescriptor, in machOFile: MachOFile) throws {
        self.descriptor = descriptor
        self.conformingTypeName = try descriptor.conformingTypeName(in: machOFile)
        self.protocolTypeName = try descriptor.protocolTypeName(in: machOFile)
        self.records = try descriptor.associatedTypeRecords(in: machOFile)
    }
}

