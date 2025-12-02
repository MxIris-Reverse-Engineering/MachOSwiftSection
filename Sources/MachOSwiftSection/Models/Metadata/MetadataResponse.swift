import Foundation
import MachOFoundation

public struct MetadataResponse {
    public let value: Pointer<MetadataWrapper>
    private let _state: Int
    public var state: MetadataState { .init(rawValue: _state)! }

    init(value: Pointer<MetadataWrapper>, state: Int = 0) {
        self.value = value
        self._state = state
    }
}
