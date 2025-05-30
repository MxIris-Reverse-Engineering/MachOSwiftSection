import Foundation
import MachOKit
import MachOSwiftSectionMacro

// using TrailingObjects
//  = swift::ABI::TrailingObjects<
//      TargetProtocolDescriptor<Runtime>,
//      TargetGenericRequirementDescriptor<Runtime>,
//      TargetProtocolRequirement<Runtime>>;

public struct Protocol {
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

    @MachOImageGenerator
    public init(descriptor: ProtocolDescriptor, in machOFile: MachOFile) throws {
        guard let protocolFlags = descriptor.flags.kindSpecificFlags?.protocolFlags else {
            throw Error.invalidProtocolDescriptor
        }
        self.descriptor = descriptor
        self.protocolFlags = protocolFlags
        self.name = try descriptor.name(in: machOFile)
        var currentOffset = descriptor.offset + descriptor.layoutSize

        if descriptor.numRequirementsInSignature > 0 {
            self.requirementInSignatures = try machOFile.readElements(offset: currentOffset, numberOfElements: descriptor.numRequirementsInSignature.cast())
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: descriptor.numRequirementsInSignature.cast())
            currentOffset = align(address: currentOffset.cast(), alignment: 4).cast()
        } else {
            self.requirementInSignatures = []
        }

        if descriptor.numRequirements > 0 {
            self.requirements = try machOFile.readElements(offset: currentOffset, numberOfElements: descriptor.numRequirements.cast())
            currentOffset.offset(of: ProtocolRequirement.self, numbersOfElements: descriptor.numRequirements.cast())
        } else {
            self.requirements = []
        }
    }
}

extension Protocol: Dumpable {
    @MachOImageGenerator
    @StringBuilder
    public func dump(using options: SymbolPrintOptions, in machOFile: MachOFile) throws -> String {
        try "protocol \(descriptor.fullname(in: machOFile))"

        if numberOfRequirementsInSignature > 0 {
            " where "

            for (offset, requirement) in requirementInSignatures.offsetEnumerated() {
                try requirement.dump(using: options, in: machOFile)
                if !offset.isEnd {
                    ", "
                }
            }
        }

        " {"

        let associatedTypes = try descriptor.associatedTypes(in: machOFile)

        if !associatedTypes.isEmpty {
            for (offset, associatedType) in associatedTypes.offsetEnumerated() {
                BreakLine()
                Indent(level: 1)
                "associatedtype \(associatedType)"
                if offset.isEnd {
                    BreakLine()
                }
            }
        }

        for (offset, requirement) in requirements.offsetEnumerated() {
            BreakLine()
            Indent(level: 1)
            if let symbol = try requirement.defaultImplementationSymbol(in: machOFile) {
                "[Default Implementation] "
                try MetadataReader.demangleSymbol(for: symbol, in: machOFile, using: options)
            } else {
                "[Stripped Symbol]"
            }
            if offset.isEnd {
                BreakLine()
            }
        }

        "}"
    }
}
