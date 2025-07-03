import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

public struct AssociatedType: TopLevelType {
    public let descriptor: AssociatedTypeDescriptor

    public let conformingTypeName: MangledName

    public let protocolTypeName: MangledName

    public let records: [AssociatedTypeRecord]

    
    public init<MachO: MachORepresentableWithCache & MachOReadable>(descriptor: AssociatedTypeDescriptor, in machOFile: MachO) throws {
        self.descriptor = descriptor
        self.conformingTypeName = try descriptor.conformingTypeName(in: machOFile)
        self.protocolTypeName = try descriptor.protocolTypeName(in: machOFile)
        self.records = try descriptor.associatedTypeRecords(in: machOFile)
    }
}

