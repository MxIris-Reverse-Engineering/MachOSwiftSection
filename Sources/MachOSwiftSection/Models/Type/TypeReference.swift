public enum TypeReference {
    case directTypeDescriptor(RelativeDirectPointer<ContextDescriptorWrapper?>)
    case indirectTypeDescriptor(RelativeDirectPointer<SignedContextPointer<ContextDescriptorWrapper?>>)
    case directObjCClassName(RelativeDirectPointer<String?>)
    case indirectObjCClass(RelativeIndirectRawPointer)
}

public enum ResolvedTypeReference {
    case directTypeDescriptor(ContextDescriptorWrapper?)
    case indirectTypeDescriptor(ResolvableElement<ContextDescriptorWrapper>?)
    case directObjCClassName(String?)
    case indirectObjCClass(Any?)
}
