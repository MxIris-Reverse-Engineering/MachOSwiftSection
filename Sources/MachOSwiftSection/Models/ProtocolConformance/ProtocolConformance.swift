import Foundation
import MachOKit
import MachOMacro
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

/// The structure of a protocol conformance.
///
/// This contains enough static information to recover the witness table for a
/// type's conformance to a protocol.

public struct ProtocolConformance: TopLevelType {
    public let descriptor: ProtocolConformanceDescriptor

    public let `protocol`: SymbolOrElement<ProtocolDescriptor>?

    public let typeReference: ResolvedTypeReference

    public let witnessTablePattern: ProtocolWitnessTable?

    public var flags: ProtocolConformanceFlags { descriptor.flags }

    public let retroactiveContextDescriptor: SymbolOrElement<ContextDescriptorWrapper>?

    public let conditionalRequirements: [GenericRequirementDescriptor]

//    public let conditionalPackShapeHeader: GenericPackShapeHeader?

    public let conditionalPackShapeDescriptors: [GenericPackShapeDescriptor]

    public let resilientWitnessesHeader: ResilientWitnessesHeader?

    public let resilientWitnesses: [ResilientWitness]

    public let genericWitnessTable: GenericWitnessTable?
    
    public init<MachO: MachORepresentableWithCache & MachOReadable>(descriptor: ProtocolConformanceDescriptor, in machO: MachO) throws {
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

        if descriptor.flags.numConditionalRequirements > 0 {
            self.conditionalRequirements = try machO.readWrapperElements(offset: currentOffset, numberOfElements: descriptor.flags.numConditionalRequirements.cast()) as [GenericRequirementDescriptor]
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: descriptor.flags.numConditionalRequirements.cast())
        } else {
            self.conditionalRequirements = []
        }

        if descriptor.flags.numConditionalPackShapeDescriptors > 0 {
//            let header: GenericPackShapeHeader = try machO.readWrapperElement(offset: currentOffset)
//            self.conditionalPackShapeHeader = header
//            currentOffset.offset(of: GenericPackShapeHeader.self)
            self.conditionalPackShapeDescriptors = try machO.readWrapperElements(offset: currentOffset, numberOfElements: descriptor.flags.numConditionalPackShapeDescriptors.cast()) as [GenericPackShapeDescriptor]
            currentOffset.offset(of: GenericPackShapeDescriptor.self, numbersOfElements: descriptor.flags.numConditionalPackShapeDescriptors.cast())
        } else {
//            self.conditionalPackShapeHeader = nil
            self.conditionalPackShapeDescriptors = []
        }

        if descriptor.flags.hasResilientWitnesses {
            let header: ResilientWitnessesHeader = try machO.readWrapperElement(offset: currentOffset)
            self.resilientWitnessesHeader = header
            currentOffset.offset(of: ResilientWitnessesHeader.self)
            self.resilientWitnesses = try machO.readWrapperElements(offset: currentOffset, numberOfElements: header.numWitnesses.cast()) as [ResilientWitness]
            currentOffset.offset(of: ResilientWitness.self, numbersOfElements: header.numWitnesses.cast())
        } else {
            self.resilientWitnessesHeader = nil
            self.resilientWitnesses = []
        }

        if descriptor.flags.hasGenericWitnessTable {
            let genericWitnessTable: GenericWitnessTable = try machO.readWrapperElement(offset: currentOffset)
            self.genericWitnessTable = genericWitnessTable
            currentOffset.offset(of: GenericWitnessTable.self)
        } else {
            self.genericWitnessTable = nil
        }
    }
}
