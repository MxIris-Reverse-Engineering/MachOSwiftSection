import Foundation
import MachOKit
import MachOBase

public typealias SwiftOnceToken = intptr_t

@ResolvableLocatableLayoutWrapper
public struct CanonicalSpecializedMetadatasCachingOnceToken {
    public struct Layout: LayoutProtocol {
        let token: RelativeDirectPointer<SwiftOnceToken>
    }
}
