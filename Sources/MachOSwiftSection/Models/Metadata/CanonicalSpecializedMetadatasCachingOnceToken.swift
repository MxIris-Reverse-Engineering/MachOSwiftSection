import Foundation
import MachOFoundation

public typealias SwiftOnceToken = intptr_t

public struct CanonicalSpecializedMetadatasCachingOnceToken: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        let token: RelativeDirectPointer<SwiftOnceToken>
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
