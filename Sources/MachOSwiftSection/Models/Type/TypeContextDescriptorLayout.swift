public protocol TypeContextDescriptorLayout: NamedContextDescriptorLayout {
    var accessFunctionPtr: RelativeOffset { get }
    var fieldDescriptor: RelativeDirectPointer<FieldDescriptor> { get }
}
