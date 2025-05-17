public enum ContextDescriptorKindSpecificFlags {
    case `protocol`(ProtocolContextDescriptorFlags)
    case type(TypeContextDescriptorFlags)
    case anonymous(AnonymousContextDescriptorFlags)
}
