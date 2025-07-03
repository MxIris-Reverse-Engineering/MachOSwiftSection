import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

public struct GenericRequirement {
    public let descriptor: GenericRequirementDescriptor

    public var flags: GenericRequirementFlags { descriptor.flags }

    public var paramManagledName: MangledName

    public var content: ResolvedGenericRequirementContent

    public init<MachO: MachORepresentableWithCache & MachOReadable>(descriptor: GenericRequirementDescriptor, in machO: MachO) throws {
        self.descriptor = descriptor
        self.paramManagledName = try descriptor.paramManagedName(in: machO)
        self.content = try descriptor.resolvedContent(in: machO)
    }
}
