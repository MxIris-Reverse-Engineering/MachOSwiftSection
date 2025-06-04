public enum Directness: UInt64, CustomStringConvertible, Sendable {
	case direct = 0
	case indirect = 1
	
	public var description: String {
		switch self {
		case .direct: return "direct"
		case .indirect: return "indirect"
		}
	}
}
