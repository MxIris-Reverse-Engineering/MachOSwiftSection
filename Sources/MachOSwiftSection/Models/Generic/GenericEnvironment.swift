import Foundation
import MachOFoundation

public struct GenericEnvironment: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let flags: GenericEnvironmentFlags
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
