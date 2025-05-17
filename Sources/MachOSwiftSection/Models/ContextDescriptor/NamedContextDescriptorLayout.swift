public protocol NamedContextDescriptorLayout: ContextDescriptorLayout {
    var name: RelativeDirectPointer<String> { get }
}
