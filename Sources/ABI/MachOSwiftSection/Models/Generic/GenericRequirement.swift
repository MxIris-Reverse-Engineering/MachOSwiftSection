import Foundation
import MachOKit
import MachOBase

public struct GenericRequirement: Sendable, TopLevelType {
    public let descriptor: GenericRequirementDescriptor

    public let paramManagledName: MangledName

    public let content: ResolvedGenericRequirementContent
}

// MARK: - ReadingContext Support

extension GenericRequirement {
    public init(descriptor: GenericRequirementDescriptor, in context: some ReadingContext) throws {
        self.descriptor = descriptor
        self.paramManagledName = try descriptor.paramMangledName(in: context)
        self.content = try descriptor.resolvedContent(in: context)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension GenericRequirement {
    @available(*, deprecated, message: "Pass a ReadingContext: GenericRequirement(descriptor:in: machO.context).")
    public init(descriptor: GenericRequirementDescriptor, in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        try self.init(descriptor: descriptor, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: GenericRequirement(descriptor:in: .inProcess).")
    public init(descriptor: GenericRequirementDescriptor) throws {
        try self.init(descriptor: descriptor, in: InProcessContext.shared)
    }
}
