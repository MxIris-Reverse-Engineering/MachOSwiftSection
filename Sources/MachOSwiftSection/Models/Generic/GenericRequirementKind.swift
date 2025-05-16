public enum GenericRequirementKind: UInt8 {
    case `protocol`
    case sameType
    case baseClass
    case sameConformance
    case sameShape
    case invertedProtocols
    case layout = 0x1F
}
