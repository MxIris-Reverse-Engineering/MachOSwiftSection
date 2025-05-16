public protocol EnumDescriptorLayout: TypeContextDescriptorLayout {
    var numPayloadCasesAndPayloadSizeOffset: UInt32 { get }
    var numEmptyCases: UInt32 { get }
}
