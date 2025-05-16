import Foundation
import MachOKit
/*
 using TrailingObjects
   = swift::ABI::TrailingObjects<
       TargetProtocolDescriptor<Runtime>,
       TargetGenericRequirementDescriptor<Runtime>,
       TargetProtocolRequirement<Runtime>>;
 */

/// A protocol descriptor.
///
/// Protocol descriptors contain information about the contents of a protocol:
/// it's name, requirements, requirement signature, context, and so on. They
/// are used both to identify a protocol and to reason about its contents.
///
/// Only Swift protocols are defined by a protocol descriptor, whereas
/// Objective-C (including protocols defined in Swift as @objc) use the
/// Objective-C protocol layout.
public struct `Protocol` {
    public let descriptor: ProtocolDescriptor
    public let requirementInSignatures: [GenericRequirement]
    public let requirements: [ProtocolRequirement]
    
    public init(from descriptor: ProtocolDescriptor, in machOFile: MachOFile) throws {
        self.descriptor = descriptor
        var currentOffset = descriptor.offset + descriptor.layoutSize
        
        if descriptor.numRequirementsInSignature > 0 {
            requirementInSignatures = try machOFile.readElements(offset: currentOffset, numberOfElements: descriptor.numRequirementsInSignature.cast()).map { try .init(descriptor: $0, in: machOFile) }
        } else {
            requirementInSignatures = []
        }
        
        currentOffset += descriptor.numRequirementsInSignature.cast() * MemoryLayout<GenericRequirementDescriptor>.size
        
        if descriptor.numRequirements > 0 {
            requirements = try machOFile.readElements(offset: currentOffset, numberOfElements: descriptor.numRequirements.cast())
        } else {
            requirements = []
        }
    }
}
