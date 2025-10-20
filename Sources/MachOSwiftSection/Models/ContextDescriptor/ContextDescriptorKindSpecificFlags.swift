public enum ContextDescriptorKindSpecificFlags: Sendable {
    case `protocol`(ProtocolContextDescriptorFlags)
    case type(TypeContextDescriptorFlags)
    case anonymous(AnonymousContextDescriptorFlags)
    
    
    public var protocolFlags: ProtocolContextDescriptorFlags? {
        switch self {
        case .protocol(let flags):
            return flags
        default:
            return nil
        }
    }
    
    public var typeFlags: TypeContextDescriptorFlags? {
        switch self {
        case .type(let flags):
            return flags
        default:
            return nil
        }
    }
    
    public var anonymousFlags: AnonymousContextDescriptorFlags? {
        switch self {
        case .anonymous(let flags):
            return flags
        default:
            return nil
        }
    }
}
