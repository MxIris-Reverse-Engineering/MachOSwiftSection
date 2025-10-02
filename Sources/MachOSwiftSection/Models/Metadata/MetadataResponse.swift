import Foundation
import MachOFoundation

public struct MetadataResponse {
    public let value: Pointer<Metadata>
    private let _state: Int
    public var state: MetadataState { .init(rawValue: _state)! }
}
