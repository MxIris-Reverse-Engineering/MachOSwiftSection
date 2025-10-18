public enum Directness: UInt64, CustomStringConvertible, CaseIterable, Sendable {
    case direct = 0
    case indirect = 1

    public var description: String {
        switch self {
        case .direct: return "direct"
        case .indirect: return "indirect"
        }
    }
}
