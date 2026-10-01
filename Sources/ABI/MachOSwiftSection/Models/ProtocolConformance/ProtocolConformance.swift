import Foundation
import MachOKit
import MachOBase

// using TrailingObjects = swift::ABI::TrailingObjects<
//                           TargetProtocolConformanceDescriptor<Runtime>,
//                           TargetRelativeContextPointer<Runtime>,       // if isRetroactive
//                           TargetGenericRequirementDescriptor<Runtime>, // numConditionalRequirements
//                           GenericPackShapeDescriptor,                  // numConditionalPackShapeDescriptors
//                           TargetResilientWitnessesHeader<Runtime>,     // if hasResilientWitnesses
//                           TargetResilientWitness<Runtime>,             // header.NumWitnesses
//                           TargetGenericWitnessTable<Runtime>,          // if hasGenericWitnessTable
//                           TargetGlobalActorReference<Runtime>>;        // if hasGlobalActorIsolation

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

    public private(set) var globalActorReference: GlobalActorReference?
}

// MARK: - ReadingContext Support

extension ProtocolConformance {
    public init(descriptor: ProtocolConformanceDescriptor, in context: some ReadingContext) throws {
        self.descriptor = descriptor

        self.protocol = try descriptor.protocolDescriptor(in: context)

        self.typeReference = try descriptor.resolvedTypeReference(in: context)

        self.witnessTablePattern = try descriptor.witnessTablePattern(in: context)

        var currentOffset = descriptor.offset + descriptor.layoutSize

        if descriptor.flags.isRetroactive {
            let retroactiveContextPointer: RelativeContextPointer = try context.readElement(at: try context.addressFromOffset(currentOffset))
            self.retroactiveContextDescriptor = try retroactiveContextPointer.resolve(at: try context.addressFromOffset(currentOffset), in: context).asOptional
            currentOffset.offset(of: RelativeIndirectablePointer<ContextDescriptorWrapper?, Pointer<ContextDescriptorWrapper?>>.self)
        } else {
            self.retroactiveContextDescriptor = nil
        }

        try initialize(descriptor: descriptor, currentOffset: &currentOffset, in: context)
    }

    private mutating func initialize(descriptor: ProtocolConformanceDescriptor, currentOffset: inout Int, in context: some ReadingContext) throws {
        if descriptor.flags.numConditionalRequirements > 0 {
            conditionalRequirements = try context.readWrapperElements(at: try context.addressFromOffset(currentOffset), numberOfElements: descriptor.flags.numConditionalRequirements.cast()) as [GenericRequirementDescriptor]
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: descriptor.flags.numConditionalRequirements.cast())
        } else {
            conditionalRequirements = []
        }

        if descriptor.flags.numConditionalPackShapeDescriptors > 0 {
            conditionalPackShapeDescriptors = try context.readWrapperElements(at: try context.addressFromOffset(currentOffset), numberOfElements: descriptor.flags.numConditionalPackShapeDescriptors.cast()) as [GenericPackShapeDescriptor]
            currentOffset.offset(of: GenericPackShapeDescriptor.self, numbersOfElements: descriptor.flags.numConditionalPackShapeDescriptors.cast())
        } else {
            conditionalPackShapeDescriptors = []
        }

        if descriptor.flags.hasResilientWitnesses {
            let header: ResilientWitnessesHeader = try context.readWrapperElement(at: try context.addressFromOffset(currentOffset))
            resilientWitnessesHeader = header
            currentOffset.offset(of: ResilientWitnessesHeader.self)
            resilientWitnesses = try context.readWrapperElements(at: try context.addressFromOffset(currentOffset), numberOfElements: header.numWitnesses.cast()) as [ResilientWitness]
            currentOffset.offset(of: ResilientWitness.self, numbersOfElements: header.numWitnesses.cast())
        } else {
            resilientWitnessesHeader = nil
            resilientWitnesses = []
        }

        if descriptor.flags.hasGenericWitnessTable {
            let genericWitnessTable: GenericWitnessTable = try context.readWrapperElement(at: try context.addressFromOffset(currentOffset))
            self.genericWitnessTable = genericWitnessTable
            currentOffset.offset(of: GenericWitnessTable.self)
        } else {
            genericWitnessTable = nil
        }

        if descriptor.flags.hasGlobalActorIsolation {
            let globalActorReference: GlobalActorReference = try context.readWrapperElement(at: try context.addressFromOffset(currentOffset))
            self.globalActorReference = globalActorReference
            currentOffset.offset(of: GlobalActorReference.self)
        } else {
            globalActorReference = nil
        }
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension ProtocolConformance {
    @available(*, deprecated, message: "Pass a ReadingContext: ProtocolConformance(descriptor:in: machO.context).")
    public init(descriptor: ProtocolConformanceDescriptor, in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        try self.init(descriptor: descriptor, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: ProtocolConformance(descriptor:in: .inProcess).")
    public init(descriptor: ProtocolConformanceDescriptor) throws {
        try self.init(descriptor: descriptor, in: InProcessContext.shared)
    }
}
