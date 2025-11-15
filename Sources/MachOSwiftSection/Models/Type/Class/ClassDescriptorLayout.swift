import Foundation
import MachOFoundation

@Layout
public protocol ClassDescriptorLayout: TypeContextDescriptorLayout {
    var superclassType: RelativeDirectPointer<MangledName?> { get }
    var metadataNegativeSizeInWordsOrResilientMetadataBounds: UInt32 { get }
    var metadataPositiveSizeInWordsOrExtraClassFlags: UInt32 { get }
    var numImmediateMembers: UInt32 { get }
    var numFields: UInt32 { get }
    var fieldOffsetVectorOffset: UInt32 { get }
}
