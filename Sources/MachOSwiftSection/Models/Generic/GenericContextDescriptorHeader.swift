@LocatableLayoutWrapping
public struct GenericContextDescriptorHeader: GenericContextDescriptorHeaderProtocol {
    public struct Layout: GenericContextDescriptorHeaderLayout {
        public let numParams: UInt16
        public let numRequirements: UInt16
        public let numKeyArguments: UInt16
        public let flags: GenericContextDescriptorFlags
    }
}
