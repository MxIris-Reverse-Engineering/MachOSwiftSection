
import MachOFoundation

@Layout
public protocol TypeContextDescriptorLayout: NamedContextDescriptorLayout {
    var accessFunctionPtr: RelativeDirectPointer<MetadataAccessor> { get }
    var fieldDescriptor: RelativeDirectPointer<FieldDescriptor> { get }
}
