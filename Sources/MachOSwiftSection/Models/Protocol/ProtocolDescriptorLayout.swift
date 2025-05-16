public protocol ProtocolDescriptorLayout: NamedContextDescriptorLayout {
    var numRequirementsInSignature: UInt32 { get }
    var numRequirements: UInt32 { get }
    var associatedTypes: RelativeDirectPointer<String> { get }
}
