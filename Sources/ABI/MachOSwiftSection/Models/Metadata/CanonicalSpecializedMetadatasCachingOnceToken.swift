import Foundation
import MachOBase

public typealias SwiftOnceToken = intptr_t

@LocatableLayoutWrapping
public struct CanonicalSpecializedMetadatasCachingOnceToken: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        let token: RelativeDirectPointer<SwiftOnceToken>
    }
}
