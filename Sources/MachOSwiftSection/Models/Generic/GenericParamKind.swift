public enum GenericParamKind: UInt8, Sendable {
    case type
    case typePack
    case value
    case max = 0x3F
}
