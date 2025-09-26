import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

public struct GenericRequirement: Sendable {
    public let descriptor: GenericRequirementDescriptor

    public var flags: GenericRequirementFlags { descriptor.flags }

    public let paramManagledName: MangledName

    public let content: ResolvedGenericRequirementContent

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(descriptor: GenericRequirementDescriptor, in machO: MachO) throws {
        self.descriptor = descriptor
        self.paramManagledName = try descriptor.paramMangledName(in: machO)
        self.content = try descriptor.resolvedContent(in: machO)
    }
}
