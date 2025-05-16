public protocol ClassDescriptorLayout: TypeContextDescriptorLayout {
    var superclassType: RelativeOffset { get }
    var metadataNegativeSizeInWordsOrResilientMetadataBounds: UInt32 { get }
    var metadataPositiveSizeInWordsOrExtraClassFlags: UInt32 { get }
    var numImmediateMembers: UInt32 { get }
    var numFields: UInt32 { get }
    var fieldOffsetVector: UInt32 { get }
}
