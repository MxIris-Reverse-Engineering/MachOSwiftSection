import Foundation
import MachOKit

public struct `Protocol` {
    public let descriptor: ProtocolDescriptor
    public let requirementInSignatures: [GenericRequirementDescriptor]
    public let requirements: [ProtocolRequirement]
    
    public init(from descriptor: ProtocolDescriptor, in machO: MachOFile) throws {
        self.descriptor = descriptor
        var currentOffset = descriptor.offset + descriptor.layoutSize
        
        if descriptor.numRequirementsInSignature > 0 {
            requirementInSignatures = try machO.readElements(offset: currentOffset.cast(), numberOfElements: descriptor.numRequirementsInSignature.cast())
        } else {
            requirementInSignatures = []
        }
        
        currentOffset += descriptor.numRequirementsInSignature.cast() * MemoryLayout<GenericRequirementDescriptor>.size
        
        if descriptor.numRequirements > 0 {
            requirements = try machO.readElements(offset: currentOffset.cast(), numberOfElements: descriptor.numRequirements.cast())
        } else {
            requirements = []
        }
        
//        for requirementInSignature in requirementInSignatures {
//            switch requirementInSignature.flags.kind {
//            case .protocol:
//                let protocolDescriptorPointer = requirementInSignature.typeOrProtocolOrConformanceOrLayoutOffset.withIntPairPointer(UInt8.self)
//                if protocolDescriptorPointer.intValue == 1 {
//                    let protocolDescriptor: ProtocolDescriptor = protocolDescriptorPointer.resolve(from: requirementInSignature.offset(of: \.typeOrProtocolOrConformanceOrLayoutOffset).cast(), in: machO)
//                } else {
//                    
//                }
//            default:
//                break
//            }
//        }
    }
}
