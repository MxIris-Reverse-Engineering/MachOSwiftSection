public protocol SwiftSectionRepresentable {
    var types: [TypeWrapper] { get throws }
    var protocols: [`Protocol`] { get throws }
    var protocolConformances: [ProtocolConformance] { get throws }
    var associatedTypes: [AssociatedType] { get throws }
    var builtinTypes: [BuiltinType] { get throws }

    var typeContextDescriptors: [TypeContextDescriptorWrapper] { get throws }
    var protocolDescriptors: [ProtocolDescriptor] { get throws }
    var protocolConformanceDescriptors: [ProtocolConformanceDescriptor] { get throws }
    var associatedTypeDescriptors: [AssociatedTypeDescriptor] { get throws }
    var builtinTypeDescriptors: [BuiltinTypeDescriptor] { get throws }
}
