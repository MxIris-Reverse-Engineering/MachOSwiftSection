import MachOBase

@Layout
public protocol ExtensionContextDescriptorLayout: ContextDescriptorLayout {
    var extendedContext: RelativeDirectPointer<MangledName?> { get }
}
