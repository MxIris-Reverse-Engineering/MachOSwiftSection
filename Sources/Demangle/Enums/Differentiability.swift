enum Differentiability: UnicodeScalar, CaseIterable, Sendable {
	case normal = "d"
	case linear = "l"
	case forward = "f"
	case reverse = "r"
	
	init?(_ uint64: UInt64) {
		guard let uint32 = UInt32(exactly: uint64), let scalar = UnicodeScalar(uint32), let value = Differentiability(rawValue: scalar) else { return nil }
		self = value
	}
}
