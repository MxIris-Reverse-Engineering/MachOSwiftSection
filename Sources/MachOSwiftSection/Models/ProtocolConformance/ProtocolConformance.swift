import Foundation
import MachOKit

// using TrailingObjects = swift::ABI::TrailingObjects<
//                           TargetProtocolConformanceDescriptor<Runtime>,
//                           TargetRelativeContextPointer<Runtime>,
//                           TargetGenericRequirementDescriptor<Runtime>,
//                           GenericPackShapeDescriptor,
//                           TargetResilientWitnessesHeader<Runtime>,
//                           TargetResilientWitness<Runtime>,
//                           TargetGenericWitnessTable<Runtime>,
//                           TargetGlobalActorReference<Runtime>>;

/// The structure of a protocol conformance.
///
/// This contains enough static information to recover the witness table for a
/// type's conformance to a protocol.
public struct ProtocolConformance {
    public let descriptor: ProtocolConformanceDescriptor

    public private(set) var `protocol`: Protocol?

    public private(set) var typeReference: ResolvedTypeReference

    public private(set) var witnessTablePattern: ProtocolWitnessTable?

    public var flags: ProtocolConformanceFlags { descriptor.flags }

    public private(set) var retroactiveContextDescriptor: ContextDescriptorWrapper?

    public private(set) var conditionalRequirements: [GenericRequirementDescriptor] = []

    public private(set) var conditionalPackShapeHeader: GenericPackShapeHeader?

    public private(set) var conditionalPackShapeDescriptors: [GenericPackShapeDescriptor] = []

    public private(set) var resilientWitnessesHeader: ResilientWitnessesHeader?

    public private(set) var resilientWitnesses: [ResilientWitness] = []

    public private(set) var genericWitnessTable: GenericWitnessTable?

    public init(descriptor: ProtocolConformanceDescriptor, in machOFile: MachOFile) throws {
        self.descriptor = descriptor

        var currentOffset = descriptor.offset + descriptor.layoutSize

        if descriptor.flags.isRetroactive {
            let retroactiveContextPointer: RelativeContextPointer<ContextDescriptorWrapper?> = try machOFile.readElement(offset: currentOffset)
            self.retroactiveContextDescriptor = try retroactiveContextPointer.resolve(from: currentOffset, in: machOFile)
            currentOffset.offset(of: RelativeIndirectablePointer<ContextDescriptorWrapper?, Pointer<ContextDescriptorWrapper?>>.self)
        }

        if descriptor.flags.numConditionalRequirements > 0 {
            self.conditionalRequirements = try machOFile.readElements(offset: currentOffset, numberOfElements: descriptor.flags.numConditionalRequirements.cast())
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: descriptor.flags.numConditionalRequirements.cast())
        }

        if descriptor.flags.numConditionalPackShapeDescriptors > 0 {
            self.conditionalPackShapeHeader = try machOFile.readElement(offset: currentOffset)
            currentOffset.offset(of: GenericPackShapeHeader.self)
            self.conditionalPackShapeDescriptors = try machOFile.readElements(offset: currentOffset, numberOfElements: descriptor.flags.numConditionalPackShapeDescriptors.cast())
            currentOffset.offset(of: GenericPackShapeDescriptor.self, numbersOfElements: descriptor.flags.numConditionalPackShapeDescriptors.cast())
        }

        if descriptor.flags.hasResilientWitnesses {
            let header: ResilientWitnessesHeader = try machOFile.readElement(offset: currentOffset)
            self.resilientWitnessesHeader = header
            currentOffset.offset(of: ResilientWitnessesHeader.self)
            self.resilientWitnesses = try machOFile.readElements(offset: currentOffset, numberOfElements: header.numWitnesses.cast())
            currentOffset.offset(of: ResilientWitness.self, numbersOfElements: header.numWitnesses.cast())
        }

        if descriptor.flags.hasGenericWitnessTable {
            let genericWitnessTable: GenericWitnessTable = try machOFile.readElement(offset: currentOffset)
            self.genericWitnessTable = genericWitnessTable
            currentOffset.offset(of: GenericWitnessTable.self)
        }

        self.protocol = try descriptor.protocolDescriptor(in: machOFile).map { try Protocol(from: $0, in: machOFile) }

        self.typeReference = try descriptor.resolvedTypeReference(in: machOFile)

        self.witnessTablePattern = try descriptor.witnessTablePattern(in: machOFile)
    }
}

