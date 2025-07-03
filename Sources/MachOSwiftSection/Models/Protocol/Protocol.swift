import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

// using TrailingObjects
//  = swift::ABI::TrailingObjects<
//      TargetProtocolDescriptor<Runtime>,
//      TargetGenericRequirementDescriptor<Runtime>,
//      TargetProtocolRequirement<Runtime>>;

public struct `Protocol`: TopLevelType {
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

    public init<MachO: MachORepresentableWithCache & MachOReadable>(descriptor: ProtocolDescriptor, in machO: MachO) throws {
        guard let protocolFlags = descriptor.flags.kindSpecificFlags?.protocolFlags else {
            throw Error.invalidProtocolDescriptor
        }
        self.descriptor = descriptor
        self.protocolFlags = protocolFlags
        self.name = try descriptor.name(in: machO)
        var currentOffset = descriptor.offset + descriptor.layoutSize

        if descriptor.numRequirementsInSignature > 0 {
            self.requirementInSignatures = try machO.readWrapperElements(offset: currentOffset, numberOfElements: descriptor.numRequirementsInSignature.cast())
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: descriptor.numRequirementsInSignature.cast())
            currentOffset = align(address: currentOffset.cast(), alignment: 4).cast()
        } else {
            self.requirementInSignatures = []
        }

        if descriptor.numRequirements > 0 {
            self.requirements = try machO.readWrapperElements(offset: currentOffset, numberOfElements: descriptor.numRequirements.cast())
            currentOffset.offset(of: ProtocolRequirement.self, numbersOfElements: descriptor.numRequirements.cast())
        } else {
            self.requirements = []
        }
    }
}
