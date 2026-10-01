import Foundation
import MachOKit
import MachOBase

// using TrailingObjects
//  = swift::ABI::TrailingObjects<
//      TargetProtocolDescriptor<Runtime>,
//      TargetGenericRequirementDescriptor<Runtime>,
//      TargetProtocolRequirement<Runtime>>;

public struct `Protocol`: TopLevelType, ContextProtocol {
    public enum Error: Swift.Error {
        case invalidProtocolDescriptor
    }

    public let descriptor: ProtocolDescriptor

    public let protocolFlags: ProtocolContextDescriptorFlags

    public let name: String

    public private(set) var baseRequirement: ProtocolBaseRequirement?
    
    public private(set) var requirementInSignatures: [GenericRequirement] = []

    public private(set) var requirements: [ProtocolRequirement] = []

    public var numberOfRequirements: Int {
        descriptor.numRequirements.cast()
    }

    public var numberOfRequirementsInSignature: Int {
        descriptor.numRequirementsInSignature.cast()
    }
}

// MARK: - ReadingContext Support

extension `Protocol` {
    public init(descriptor: ProtocolDescriptor, in context: some ReadingContext) throws {
        guard let protocolFlags = descriptor.flags.kindSpecificFlags?.protocolFlags else {
            throw Error.invalidProtocolDescriptor
        }
        self.descriptor = descriptor
        self.protocolFlags = protocolFlags
        self.name = try descriptor.name(in: context)
        var currentOffset = descriptor.offset + descriptor.layoutSize
        if descriptor.numRequirementsInSignature > 0 {
            let requirementInSignatures = try context.readWrapperElements(at: try context.addressFromOffset(currentOffset), numberOfElements: descriptor.numRequirementsInSignature.cast()) as [GenericRequirementDescriptor]
            self.requirementInSignatures = try requirementInSignatures.map { try .init(descriptor: $0, in: context) }
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: descriptor.numRequirementsInSignature.cast())
            currentOffset.align(to: 4)
        } else {
            self.requirementInSignatures = []
        }
        try initialize(descriptor: descriptor, currentOffset: &currentOffset, in: context)
    }

    private mutating func initialize(descriptor: ProtocolDescriptor, currentOffset: inout Int, in context: some ReadingContext) throws {
        if descriptor.numRequirements > 0 {
            let baseRequirementOffset = currentOffset - ProtocolRequirement.layoutSize
            baseRequirement = try context.readWrapperElement(at: try context.addressFromOffset(baseRequirementOffset)) as ProtocolBaseRequirement
            requirements = try context.readWrapperElements(at: try context.addressFromOffset(currentOffset), numberOfElements: descriptor.numRequirements.cast()) as [ProtocolRequirement]
            currentOffset.offset(of: ProtocolRequirement.self, numbersOfElements: descriptor.numRequirements.cast())
        } else {
            baseRequirement = nil
            requirements = []
        }
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension `Protocol` {
    @available(*, deprecated, message: "Pass a ReadingContext: Protocol(descriptor:in: machO.context).")
    public init(descriptor: ProtocolDescriptor, in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        try self.init(descriptor: descriptor, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: Protocol(descriptor:in: .inProcess).")
    public init(descriptor: ProtocolDescriptor) throws {
        try self.init(descriptor: descriptor, in: InProcessContext.shared)
    }
}
