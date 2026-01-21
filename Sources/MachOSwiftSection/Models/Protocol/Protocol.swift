import Foundation
import MachOKit
import MachOFoundation

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

    public private(set) var requirementInSignatures: [GenericRequirement] = []

    public private(set) var requirements: [ProtocolRequirement] = []

    public var numberOfRequirements: Int {
        descriptor.numRequirements.cast()
    }

    public var numberOfRequirementsInSignature: Int {
        descriptor.numRequirementsInSignature.cast()
    }

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(descriptor: ProtocolDescriptor, in machO: MachO) throws {
        guard let protocolFlags = descriptor.flags.kindSpecificFlags?.protocolFlags else {
            throw Error.invalidProtocolDescriptor
        }
        self.descriptor = descriptor
        self.protocolFlags = protocolFlags
        self.name = try descriptor.name(in: machO)
        var currentOffset = descriptor.offset + descriptor.layoutSize
        if descriptor.numRequirementsInSignature > 0 {
            let requirementInSignatures = try machO.readWrapperElements(offset: currentOffset, numberOfElements: descriptor.numRequirementsInSignature.cast()) as [GenericRequirementDescriptor]
            self.requirementInSignatures = try requirementInSignatures.map { try .init(descriptor: $0, in: machO) }
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: descriptor.numRequirementsInSignature.cast())
            currentOffset.align(to: 4)
        } else {
            self.requirementInSignatures = []
        }
        try initialize(descriptor: descriptor, currentOffset: &currentOffset, in: machO)
    }

    public init(descriptor: ProtocolDescriptor) throws {
        guard let protocolFlags = descriptor.flags.kindSpecificFlags?.protocolFlags else {
            throw Error.invalidProtocolDescriptor
        }
        self.descriptor = descriptor
        self.protocolFlags = protocolFlags
        self.name = try descriptor.name()
        var currentOffset = descriptor.layoutSize
        let pointer = try descriptor.asPointer
        if descriptor.numRequirementsInSignature > 0 {
            let requirementInSignatures = try pointer.readWrapperElements(offset: currentOffset, numberOfElements: descriptor.numRequirementsInSignature.cast()) as [GenericRequirementDescriptor]
            self.requirementInSignatures = try requirementInSignatures.map { try .init(descriptor: $0) }
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: descriptor.numRequirementsInSignature.cast())
            currentOffset.align(to: 4)
        } else {
            self.requirementInSignatures = []
        }
        try initialize(descriptor: descriptor, currentOffset: &currentOffset, in: pointer)
    }

    private mutating func initialize<Reader: Readable>(descriptor: ProtocolDescriptor, currentOffset: inout Int, in reader: Reader) throws {
        if descriptor.numRequirements > 0 {
            requirements = try reader.readWrapperElements(offset: currentOffset, numberOfElements: descriptor.numRequirements.cast()) as [ProtocolRequirement]
            currentOffset.offset(of: ProtocolRequirement.self, numbersOfElements: descriptor.numRequirements.cast())
        } else {
            requirements = []
        }
    }
}
