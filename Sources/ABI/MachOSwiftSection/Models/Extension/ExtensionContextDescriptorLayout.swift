import MachOBase
import Utilities

@Layout
public protocol ExtensionContextDescriptorLayout: ContextDescriptorLayout {
    var extendedContext: RelativeDirectPointer<MangledName?> { get }
}
