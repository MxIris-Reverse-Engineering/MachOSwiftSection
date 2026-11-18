
import MachOBase
import Utilities

@Layout
public protocol TypeContextDescriptorLayout: NamedContextDescriptorLayout {
    var accessFunctionPtr: RelativeDirectPointer<MetadataAccessorFunction> { get }
    var fieldDescriptor: RelativeDirectPointer<FieldDescriptor> { get }
}
