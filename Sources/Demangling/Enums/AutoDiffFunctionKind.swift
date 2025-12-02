enum AutoDiffFunctionKind: UnicodeScalar, CaseIterable, Sendable {
    case forward = "f"
    case reverse = "r"
    case differential = "d"
    case pullback = "p"

    init?(_ uint64: UInt64) {
        guard let uint32 = UInt32(exactly: uint64), let scalar = UnicodeScalar(uint32), let value = AutoDiffFunctionKind(rawValue: scalar) else { return nil }
        self = value
    }
}
