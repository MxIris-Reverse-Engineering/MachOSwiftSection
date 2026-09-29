public enum FieldDescriptorKind: UInt16 {
    case `struct`
    case `class`
    case `enum`
    case multiPayloadEnum
    case `protocol`
    case classProtocol
    case objCProtocol
    case objCClass
    case unknown = 0xFFFF
}
