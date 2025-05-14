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
    
    public private(set) var `protocol`: `Protocol`?
    
    public private(set) var typeReference: ResolvedTypeReference?
    
    public private(set) var retroactiveContextDescriptor: ContextDescriptorWrapper?
    
    public private(set) var conditionalRequirements: [GenericRequirementDescriptor] = []
    
    public private(set) var conditionalPackShapeHeader: GenericPackShapeHeader?
    
    public private(set) var conditionalPackShapeDescriptors: [GenericPackShapeDescriptor] = []
    
    public private(set) var resilientWitnessesHeader: ResilientWitnessesHeader?
    
    public private(set) var resilientWitnesses: [ResilientWitness] = []
    
    public private(set) var genericWitnessTable: GenericWitnessTable?
    
    
    public init(descriptor: ProtocolConformanceDescriptor, in machO: MachOFile) throws {
        self.descriptor = descriptor
        
        var currentOffset = descriptor.offset + descriptor.layoutSize
        
        if descriptor.flags.isRetroactive {
            let retroactiveContextPointer: RelativeIndirectablePointer<ContextDescriptorWrapper?, Pointer<ContextDescriptorWrapper?>> = try machO.readElement(offset: currentOffset)
            retroactiveContextDescriptor = try retroactiveContextPointer.resolve(from: currentOffset, in: machO)
            currentOffset.offset(of: RelativeIndirectablePointer<ContextDescriptorWrapper?, Pointer<ContextDescriptorWrapper?>>.self)
        }
        
        if descriptor.flags.numConditionalRequirements > 0 {
            conditionalRequirements = try machO.readElements(offset: currentOffset, numberOfElements: descriptor.flags.numConditionalRequirements.cast())
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: descriptor.flags.numConditionalRequirements.cast())
        }
        
        if descriptor.flags.numConditionalPackShapeDescriptors > 0 {
            conditionalPackShapeHeader = try machO.readElement(offset: currentOffset)
            currentOffset.offset(of: GenericPackShapeHeader.self)
            conditionalPackShapeDescriptors = try machO.readElements(offset: currentOffset, numberOfElements: descriptor.flags.numConditionalPackShapeDescriptors.cast())
            currentOffset.offset(of: GenericPackShapeDescriptor.self, numbersOfElements: descriptor.flags.numConditionalPackShapeDescriptors.cast())
        }
        
        if descriptor.flags.hasResilientWitnesses {
            let header: ResilientWitnessesHeader = try machO.readElement(offset: currentOffset)
            resilientWitnessesHeader = header
            currentOffset.offset(of: ResilientWitnessesHeader.self)
            resilientWitnesses = try machO.readElements(offset: currentOffset, numberOfElements: header.numWitnesses.cast())
            currentOffset.offset(of: ResilientWitness.self, numbersOfElements: header.numWitnesses.cast())
        }
        
        if descriptor.flags.hasGenericWitnessTable {
            let genericWitnessTable: GenericWitnessTable = try machO.readElement(offset: currentOffset)
            self.genericWitnessTable = genericWitnessTable
            currentOffset.offset(of: GenericWitnessTable.self)
        }
        
        if let protocolDescriptor = try descriptor.protocolDescriptor(in: machO) {
            self.protocol = try Protocol(from: protocolDescriptor, in: machO)
        }
        
    }
}

extension BinaryInteger {
    mutating func offset<T>(of type: T.Type, numbersOfElements: Int = 1) {
        self += numericCast(MemoryLayout<T>.size * numbersOfElements)
    }
    
    mutating func offset<T: LayoutWrapper>(of type: T.Type, numbersOfElements: Int = 1) {
        self += numericCast(MemoryLayout<T.Layout>.size * numbersOfElements)
    }
    
    func offseting<T>(of type: T.Type, numbersOfElements: Int = 1) -> Self {
        return self * numericCast(MemoryLayout<T>.size * numbersOfElements)
    }
}
