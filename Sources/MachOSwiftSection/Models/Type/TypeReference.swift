public enum TypeReference {
    case directTypeDescriptor(RelativeDirectPointer<ContextDescriptorWrapper?>)
    case indirectTypeDescriptor(RelativeIndirectPointer<ContextDescriptorWrapper?, SignedPointer<ContextDescriptorWrapper?>>)
    case directObjCClassName(RelativeDirectPointer<String?>)
    case indirectObjCClass(RelativeIndirectRawPointer)
}

public enum ResolvedTypeReference {
    case directTypeDescriptor(ContextDescriptorWrapper?)
    case indirectTypeDescriptor(ContextDescriptorWrapper?)
    case directObjCClassName(String?)
    case indirectObjCClass(Any?)
}
