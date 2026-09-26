import MachOKit

public protocol OpaqueTypeDescriptorProtocol: ContextDescriptorProtocol where Layout: OpaqueTypeDescriptorLayout {}

extension OpaqueTypeDescriptorProtocol {
    /// How many underlying type arguments trail the descriptor: one
    /// replacement type per opaque result type, then one witness table per
    /// conformance requirement rooted at the opaque parameters' depth
    /// (`OpaqueTypeDescriptorBuilder::getKindSpecificFlags` in IRGen).
    public var numUnderlyingTypeArguments: Int {
        layout.flags.kindSpecificFlagsRawValue.cast()
    }

    @available(*, deprecated, renamed: "numUnderlyingTypeArguments")
    public var numUnderlyingTypeArugments: Int {
        numUnderlyingTypeArguments
    }
}
