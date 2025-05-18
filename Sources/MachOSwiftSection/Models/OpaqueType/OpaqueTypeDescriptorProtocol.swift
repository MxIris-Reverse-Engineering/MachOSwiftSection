import MachOKit

public protocol OpaqueTypeDescriptorProtocol: ContextDescriptorProtocol where Layout: OpaqueTypeDescriptorLayout {}

extension OpaqueTypeDescriptorProtocol {
    public var numUnderlyingTypeArugments: Int {
        layout.flags.kindSpecificFlagsRawValue.cast()
    }
}
