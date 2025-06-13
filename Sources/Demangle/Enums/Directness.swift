package enum Directness: UInt64, CustomStringConvertible, CaseIterable, Sendable {
    case direct = 0
    case indirect = 1

    package var description: String {
        switch self {
        case .direct: return "direct"
        case .indirect: return "indirect"
        }
    }
}
