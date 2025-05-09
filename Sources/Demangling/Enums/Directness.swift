enum Directness: UInt64, CustomStringConvertible {
	case direct = 0
	case indirect = 1
	
	var description: String {
		switch self {
		case .direct: return "direct"
		case .indirect: return "indirect"
		}
	}
}
