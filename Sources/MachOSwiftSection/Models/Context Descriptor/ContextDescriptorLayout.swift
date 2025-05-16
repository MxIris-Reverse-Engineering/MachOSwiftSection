public protocol ContextDescriptorLayout {
    var flags: ContextDescriptorFlags { get }
    var parent: RelativeIndirectablePointer<ContextDescriptorWrapper?, SignedPointer<ContextDescriptorWrapper?>> { get }
}
