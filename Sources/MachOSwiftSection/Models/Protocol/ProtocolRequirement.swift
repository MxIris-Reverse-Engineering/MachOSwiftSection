import Foundation

public struct ProtocolRequirement: LocatableLayoutWrapper, Resolvable {
    public struct Layout {
        public let flags: ProtocolRequirementFlags
        public let defaultImplementation: RelativeOffset
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}




