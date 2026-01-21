import Foundation
import MachOKit
import MachOFoundation

// using TrailingObjects = swift::ABI::TrailingObjects<
//                           TargetProtocolConformanceDescriptor<Runtime>,
//                           TargetRelativeContextPointer<Runtime>,
//                           TargetGenericRequirementDescriptor<Runtime>,
//                           GenericPackShapeDescriptor,
//                           TargetResilientWitnessesHeader<Runtime>,
//                           TargetResilientWitness<Runtime>,
//                           TargetGenericWitnessTable<Runtime>,
//                           TargetGlobalActorReference<Runtime>>;

// The structure of a protocol conformance.
//
// This contains enough static information to recover the witness table for a
// type's conformance to a protocol.

public struct ProtocolConformance: TopLevelType {
    public let descriptor: ProtocolConformanceDescriptor

    public var flags: ProtocolConformanceFlags { descriptor.flags }

    public private(set) var `protocol`: SymbolOrElement<ProtocolDescriptor>?

    public private(set) var typeReference: ResolvedTypeReference

    public private(set) var witnessTablePattern: ProtocolWitnessTable?

    public private(set) var retroactiveContextDescriptor: SymbolOrElement<ContextDescriptorWrapper>?

    public private(set) var conditionalRequirements: [GenericRequirementDescriptor] = []

    public private(set) var conditionalPackShapeDescriptors: [GenericPackShapeDescriptor] = []

    public private(set) var resilientWitnessesHeader: ResilientWitnessesHeader?

    public private(set) var resilientWitnesses: [ResilientWitness] = []

    public private(set) var genericWitnessTable: GenericWitnessTable?

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(descriptor: ProtocolConformanceDescriptor, in machO: MachO) throws {
        self.descriptor = descriptor

        self.protocol = try descriptor.protocolDescriptor(in: machO)

        self.typeReference = try descriptor.resolvedTypeReference(in: machO)

        self.witnessTablePattern = try descriptor.witnessTablePattern(in: machO)

        var currentOffset = descriptor.offset + descriptor.layoutSize

        if descriptor.flags.isRetroactive {
            let retroactiveContextPointer: RelativeContextPointer = try machO.readElement(offset: currentOffset)
            self.retroactiveContextDescriptor = try retroactiveContextPointer.resolve(from: currentOffset, in: machO).asOptional
            currentOffset.offset(of: RelativeIndirectablePointer<ContextDescriptorWrapper?, Pointer<ContextDescriptorWrapper?>>.self)
        } else {
            self.retroactiveContextDescriptor = nil
        }

        try initialize(descriptor: descriptor, currentOffset: &currentOffset, in: machO)
    }

    public init(descriptor: ProtocolConformanceDescriptor) throws {
        self.descriptor = descriptor

        self.protocol = try descriptor.protocolDescriptor()

        self.typeReference = try descriptor.resolvedTypeReference()

        self.witnessTablePattern = try descriptor.witnessTablePattern()

        var currentOffset = descriptor.layoutSize

        let pointer = try descriptor.asPointer

        if descriptor.flags.isRetroactive {
            let retroactiveContextPointer: RelativeContextPointer = try pointer.readElement(offset: currentOffset)
            self.retroactiveContextDescriptor = try retroactiveContextPointer.resolve(from: pointer.advanced(by: currentOffset)).asOptional
            currentOffset.offset(of: RelativeIndirectablePointer<ContextDescriptorWrapper?, Pointer<ContextDescriptorWrapper?>>.self)
        } else {
            self.retroactiveContextDescriptor = nil
        }

        try initialize(descriptor: descriptor, currentOffset: &currentOffset, in: pointer)
    }

    private mutating func initialize<Reader: Readable>(descriptor: ProtocolConformanceDescriptor, currentOffset: inout Int, in reader: Reader) throws {
        if descriptor.flags.numConditionalRequirements > 0 {
            conditionalRequirements = try reader.readWrapperElements(offset: currentOffset, numberOfElements: descriptor.flags.numConditionalRequirements.cast()) as [GenericRequirementDescriptor]
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: descriptor.flags.numConditionalRequirements.cast())
        } else {
            conditionalRequirements = []
        }

        if descriptor.flags.numConditionalPackShapeDescriptors > 0 {
            conditionalPackShapeDescriptors = try reader.readWrapperElements(offset: currentOffset, numberOfElements: descriptor.flags.numConditionalPackShapeDescriptors.cast()) as [GenericPackShapeDescriptor]
            currentOffset.offset(of: GenericPackShapeDescriptor.self, numbersOfElements: descriptor.flags.numConditionalPackShapeDescriptors.cast())
        } else {
            conditionalPackShapeDescriptors = []
        }

        if descriptor.flags.hasResilientWitnesses {
            let header: ResilientWitnessesHeader = try reader.readWrapperElement(offset: currentOffset)
            resilientWitnessesHeader = header
            currentOffset.offset(of: ResilientWitnessesHeader.self)
            resilientWitnesses = try reader.readWrapperElements(offset: currentOffset, numberOfElements: header.numWitnesses.cast()) as [ResilientWitness]
            currentOffset.offset(of: ResilientWitness.self, numbersOfElements: header.numWitnesses.cast())
        } else {
            resilientWitnessesHeader = nil
            resilientWitnesses = []
        }

        if descriptor.flags.hasGenericWitnessTable {
            let genericWitnessTable: GenericWitnessTable = try reader.readWrapperElement(offset: currentOffset)
            self.genericWitnessTable = genericWitnessTable
            currentOffset.offset(of: GenericWitnessTable.self)
        } else {
            genericWitnessTable = nil
        }
    }
}
