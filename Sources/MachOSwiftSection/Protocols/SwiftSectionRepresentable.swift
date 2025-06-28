public protocol SwiftSectionRepresentable {
    var protocolDescriptors: [ProtocolDescriptor] { get throws }

    var protocolConformanceDescriptors: [ProtocolConformanceDescriptor] { get throws }

    var typeContextDescriptors: [ContextDescriptorWrapper] { get throws }

    var associatedTypeDescriptors: [AssociatedTypeDescriptor] { get throws }

    var builtinTypeDescriptors: [BuiltinTypeDescriptor] { get throws }
}
