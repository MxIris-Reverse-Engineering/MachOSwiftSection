import Foundation
import MachOKit

public struct GenericRequirement {
    public let descriptor: GenericRequirementDescriptor

    public var flags: GenericRequirementFlags { descriptor.flags }

    public var paramManagledName: MangledName

    public var content: ResolvedGenericRequirementContent

    public init(descriptor: GenericRequirementDescriptor, in machOFile: MachOFile) throws {
        self.descriptor = descriptor
        self.paramManagledName = try descriptor.paramManagedName(in: machOFile)
        self.content = try descriptor.resolvedContent(in: machOFile)
    }
}
