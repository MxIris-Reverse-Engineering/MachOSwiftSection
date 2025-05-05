import Foundation
import MachOKit

/*
 using TrailingObjects = swift::ABI::TrailingObjects<
                            TargetProtocolConformanceDescriptor<Runtime>,
                            TargetRelativeContextPointer<Runtime>,
                            TargetGenericRequirementDescriptor<Runtime>,
                            GenericPackShapeDescriptor,
                            TargetResilientWitnessesHeader<Runtime>,
                            TargetResilientWitness<Runtime>,
                            TargetGenericWitnessTable<Runtime>,
                            TargetGlobalActorReference<Runtime>>;
 */

/// The structure of a protocol conformance.
///
/// This contains enough static information to recover the witness table for a
/// type's conformance to a protocol.
public struct ProtocolConformance {
    public let descriptor: ProtocolConformanceDescriptor

    public init(descriptor: ProtocolConformanceDescriptor, in machO: MachOFile) throws {
        self.descriptor = descriptor
        
        var currentOffset = descriptor.offset + descriptor.layoutSize
        
        if descriptor.flags.isRetroactive {
            let retroactiveContextPointer: RelativeIndirectablePointer<ContextDescriptor> = try machO.fileHandle.read(offset: numericCast(currentOffset + machO.headerStartOffset))
            currentOffset.offset(of: RelativeIndirectablePointer<ContextDescriptor>.self)
        }
        
        if descriptor.flags.numConditionalRequirements > 0 {
            let conditionalRequirements: [GenericRequirementDescriptor] = try machO.readElements(offset: numericCast(currentOffset + machO.headerStartOffset), numberOfElements: descriptor.flags.numConditionalRequirements.cast())
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: descriptor.flags.numConditionalRequirements.cast())
        }
        
        if descriptor.flags.numConditionalPackShapeDescriptors > 0 {
            let header: GenericPackShapeHeader = try machO.fileHandle.read(offset: numericCast(currentOffset + machO.headerStartOffset))
            currentOffset.offset(of: GenericPackShapeHeader.self)
            let conditionalPackShapeDescriptors: [GenericPackShapeDescriptor] = try machO.readElements(offset: numericCast(currentOffset + machO.headerStartOffset), numberOfElements: descriptor.flags.numConditionalPackShapeDescriptors.cast())
            currentOffset.offset(of: GenericPackShapeDescriptor.self, numbersOfElements: descriptor.flags.numConditionalPackShapeDescriptors.cast())
        }
        
        if descriptor.flags.hasResilientWitnesses {
            let header: ResilientWitnessesHeader = try machO.fileHandle.read(offset: numericCast(currentOffset + machO.headerStartOffset))
            currentOffset.offset(of: ResilientWitnessesHeader.self)
            let resilientWitnesses: [ResilientWitness] = try machO.readElements(offset: numericCast(currentOffset + machO.headerStartOffset), numberOfElements: header.numWitnesses.cast())
            currentOffset.offset(of: ResilientWitness.self, numbersOfElements: header.numWitnesses.cast())
        }
        
        if descriptor.flags.hasGenericWitnessTable {
            let genericWitnessTable: GenericWitnessTable = try machO.fileHandle.read(offset: numericCast(currentOffset + machO.headerStartOffset))
            currentOffset.offset(of: GenericWitnessTable.self)
        }
        
        if let protocolDescriptor = try descriptor.protocolDescriptor(in: machO) {
            
        }
    }
}

extension BinaryInteger {
    mutating func offset<T>(of type: T.Type, numbersOfElements: Int = 1) {
        self += numericCast(MemoryLayout<T>.size * numbersOfElements)
    }
    func offseting<T>(of type: T.Type, numbersOfElements: Int = 1) -> Self {
        return self * numericCast(MemoryLayout<T>.size * numbersOfElements)
    }
}
