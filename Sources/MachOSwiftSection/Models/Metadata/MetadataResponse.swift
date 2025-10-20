import Foundation
import MachOFoundation

public struct MetadataResponse {
    public let value: Pointer<MetadataWrapper>
    private let _state: Int
    public var state: MetadataState { .init(rawValue: _state)! }
}
