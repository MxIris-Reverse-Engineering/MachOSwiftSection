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

    public let `protocol`: ResolvableElement<Protocol>?

    public let typeReference: ResolvedTypeReference

    public let witnessTablePattern: ProtocolWitnessTable?

    public var flags: ProtocolConformanceFlags { descriptor.flags }

    public let retroactiveContextDescriptor: ResolvableElement<ContextDescriptorWrapper>?

    public let conditionalRequirements: [GenericRequirement]

    public let conditionalPackShapeHeader: GenericPackShapeHeader?

    public let conditionalPackShapeDescriptors: [GenericPackShapeDescriptor]

    public let resilientWitnessesHeader: ResilientWitnessesHeader?

    public let resilientWitnesses: [ResilientWitness]

    public let genericWitnessTable: GenericWitnessTable?

    public init(descriptor: ProtocolConformanceDescriptor, in machOFile: MachOFile) throws {
        self.descriptor = descriptor
        
        self.protocol = try descriptor.protocolDescriptor(in: machOFile).map {
            switch $0 {
            case .symbol(let symbol): return .symbol(symbol)
            case .element(let element): return .element(try Protocol(descriptor: element, in: machOFile))
            }
        }

        self.typeReference = try descriptor.resolvedTypeReference(in: machOFile)

        self.witnessTablePattern = try descriptor.witnessTablePattern(in: machOFile)
        
        var currentOffset = descriptor.offset + descriptor.layoutSize

        if descriptor.flags.isRetroactive {
            let retroactiveContextPointer: RelativeContextPointer<ContextDescriptorWrapper?> = try machOFile.readElement(offset: currentOffset)
            self.retroactiveContextDescriptor = try retroactiveContextPointer.resolve(from: currentOffset, in: machOFile).asOptional
            currentOffset.offset(of: RelativeIndirectablePointer<ContextDescriptorWrapper?, Pointer<ContextDescriptorWrapper?>>.self)
        } else {
            self.retroactiveContextDescriptor = nil
        }

        if descriptor.flags.numConditionalRequirements > 0 {
            self.conditionalRequirements = try machOFile.readElements(offset: currentOffset, numberOfElements: descriptor.flags.numConditionalRequirements.cast()).map { try .init(descriptor: $0, in: machOFile) }
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: descriptor.flags.numConditionalRequirements.cast())
        } else {
            self.conditionalRequirements = []
        }

        if descriptor.flags.numConditionalPackShapeDescriptors > 0 {
            self.conditionalPackShapeHeader = try machOFile.readElement(offset: currentOffset)
            currentOffset.offset(of: GenericPackShapeHeader.self)
            self.conditionalPackShapeDescriptors = try machOFile.readElements(offset: currentOffset, numberOfElements: descriptor.flags.numConditionalPackShapeDescriptors.cast())
            currentOffset.offset(of: GenericPackShapeDescriptor.self, numbersOfElements: descriptor.flags.numConditionalPackShapeDescriptors.cast())
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

//extension ProtocolConformance: CustomStringConvertible {
//    public var description: String {
//        switch typeReference {
//        case .directTypeDescriptor(let descriptor):
//            break
//        case .indirectTypeDescriptor(let descriptor):
//            break
//        case .directObjCClassName(let objcClassName):
//            break
//        case .indirectObjCClass(let objcClass):
//            break
//        }
//    }
//}
