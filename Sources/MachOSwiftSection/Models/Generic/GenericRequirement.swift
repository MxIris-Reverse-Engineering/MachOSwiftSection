import Foundation
import MachOKit
import MachOFoundation

public struct GenericRequirement: Sendable, TopLevelType {
    public let descriptor: GenericRequirementDescriptor

    public let paramManagledName: MangledName

    public let content: ResolvedGenericRequirementContent

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(descriptor: GenericRequirementDescriptor, in machO: MachO) throws {
        self.descriptor = descriptor
        self.paramManagledName = try descriptor.paramMangledName(in: machO)
        self.content = try descriptor.resolvedContent(in: machO)
    }
    
    public init(descriptor: GenericRequirementDescriptor) throws {
        self.descriptor = descriptor
        self.paramManagledName = try descriptor.paramMangledName()
        self.content = try descriptor.resolvedContent()
    }
}

// MARK: - ReadingContext Support

extension GenericRequirement {
    public init<Context: ReadingContext>(descriptor: GenericRequirementDescriptor, in context: Context) throws {
        self.descriptor = descriptor
        self.paramManagledName = try descriptor.paramMangledName(in: context)
        self.content = try descriptor.resolvedContent(in: context)
    }
}
