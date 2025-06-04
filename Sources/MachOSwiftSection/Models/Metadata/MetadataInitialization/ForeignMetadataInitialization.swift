import Foundation
import MachOFoundation

public struct ForeignMetadataInitialization: ResolvableLocatableLayoutWrapper {
    public struct Layout: Sendable {
        public let completionFunction: RelativeDirectRawPointer
    }

    public let offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
