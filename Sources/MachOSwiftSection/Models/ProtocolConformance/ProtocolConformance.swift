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
public struct ProtocolConformance {
    public let descriptor: ProtocolConformanceDescriptor

    public let `protocol`: SymbolOrElement<ProtocolDescriptor>?

    public let typeReference: ResolvedTypeReference

    public let witnessTablePattern: ProtocolWitnessTable?

    public var flags: ProtocolConformanceFlags { descriptor.flags }

    public let retroactiveContextDescriptor: SymbolOrElement<ContextDescriptorWrapper>?

    public let conditionalRequirements: [GenericRequirementDescriptor]

    public let conditionalPackShapeHeader: GenericPackShapeHeader?

    public let conditionalPackShapeDescriptors: [GenericPackShapeDescriptor]

    public let resilientWitnessesHeader: ResilientWitnessesHeader?

    public let resilientWitnesses: [ResilientWitness]

    public let genericWitnessTable: GenericWitnessTable?
    
    @MachOImageGenerator
    public init(descriptor: ProtocolConformanceDescriptor, in machOFile: MachOFile) throws {
        self.descriptor = descriptor

        self.protocol = try descriptor.protocolDescriptor(in: machOFile)

        self.typeReference = try descriptor.resolvedTypeReference(in: machOFile)

        self.witnessTablePattern = try descriptor.witnessTablePattern(in: machOFile)

        var currentOffset = descriptor.offset + descriptor.layoutSize

        if descriptor.flags.isRetroactive {
            let retroactiveContextPointer: RelativeContextPointer = try machOFile.readElement(offset: currentOffset)
            self.retroactiveContextDescriptor = try retroactiveContextPointer.resolve(from: currentOffset, in: machOFile).asOptional
            currentOffset.offset(of: RelativeIndirectablePointer<ContextDescriptorWrapper?, Pointer<ContextDescriptorWrapper?>>.self)
        } else {
            self.retroactiveContextDescriptor = nil
        }

        if descriptor.flags.numConditionalRequirements > 0 {
            self.conditionalRequirements = try machOFile.readElements(offset: currentOffset, numberOfElements: descriptor.flags.numConditionalRequirements.cast())
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: descriptor.flags.numConditionalRequirements.cast())
        } else {
            self.conditionalRequirements = []
        }

        if descriptor.flags.numConditionalPackShapeDescriptors > 0 {
            let header: GenericPackShapeHeader = try machOFile.readElement(offset: currentOffset)
            self.conditionalPackShapeHeader = header
            currentOffset.offset(of: GenericPackShapeHeader.self)
            self.conditionalPackShapeDescriptors = try machOFile.readWrapperElements(offset: currentOffset, numberOfElements: header.numPacks.cast())
            currentOffset.offset(of: GenericPackShapeDescriptor.self, numbersOfElements: header.numPacks.cast())
        } else {
            self.conditionalPackShapeHeader = nil
            self.conditionalPackShapeDescriptors = []
        }

        if descriptor.flags.hasResilientWitnesses {
            let header: ResilientWitnessesHeader = try machOFile.readElement(offset: currentOffset)
            self.resilientWitnessesHeader = header
            currentOffset.offset(of: ResilientWitnessesHeader.self)
            self.resilientWitnesses = try machOFile.readElements(offset: currentOffset, numberOfElements: header.numWitnesses.cast())
            currentOffset.offset(of: ResilientWitness.self, numbersOfElements: header.numWitnesses.cast())
        } else {
            self.resilientWitnessesHeader = nil
            self.resilientWitnesses = []
        }

        if descriptor.flags.hasGenericWitnessTable {
            let genericWitnessTable: GenericWitnessTable = try machOFile.readElement(offset: currentOffset)
            self.genericWitnessTable = genericWitnessTable
            currentOffset.offset(of: GenericWitnessTable.self)
        } else {
            self.genericWitnessTable = nil
        }
    }
}
