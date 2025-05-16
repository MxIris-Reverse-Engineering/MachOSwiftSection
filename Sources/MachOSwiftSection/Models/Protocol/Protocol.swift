import Foundation
import MachOKit

// using TrailingObjects
//  = swift::ABI::TrailingObjects<
//      TargetProtocolDescriptor<Runtime>,
//      TargetGenericRequirementDescriptor<Runtime>,
//      TargetProtocolRequirement<Runtime>>;

public struct `Protocol` {
    public enum Error: Swift.Error {
        case invalidProtocolDescriptor
    }

    public let descriptor: ProtocolDescriptor

    public let requirementInSignatures: [GenericRequirementDescriptor]

    public let requirements: [ProtocolRequirement]

    public let protocolFlags: ProtocolContextDescriptorFlags

    public let name: String

    public var numberOfRequirements: Int {
        descriptor.numRequirements.cast()
    }

    public var numberOfRequirementsInSignature: Int {
        descriptor.numRequirementsInSignature.cast()
    }

    public init(descriptor: ProtocolDescriptor, in machOFile: MachOFile) throws {
        guard case .protocol(let protocolFlags) = descriptor.flags.kindSpecificFlags else {
            throw Error.invalidProtocolDescriptor
        }
        self.descriptor = descriptor
        self.protocolFlags = protocolFlags
        self.name = try descriptor.name(in: machOFile)
        var currentOffset = descriptor.offset + descriptor.layoutSize

        if descriptor.numRequirementsInSignature > 0 {
            self.requirementInSignatures = try machOFile.readElements(offset: currentOffset, numberOfElements: descriptor.numRequirementsInSignature.cast())
        } else {
            self.requirementInSignatures = []
        }

        currentOffset += descriptor.numRequirementsInSignature.cast() * MemoryLayout<GenericRequirementDescriptor>.size

        if descriptor.numRequirements > 0 {
            self.requirements = try machOFile.readElements(offset: currentOffset, numberOfElements: descriptor.numRequirements.cast())
        } else {
            self.requirements = []
        }
    }
}
