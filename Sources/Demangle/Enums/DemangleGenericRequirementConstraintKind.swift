enum DemangleGenericRequirementConstraintKind: Sendable {
	case `protocol`
	case baseClass
	case sameType
	case sameShape
	case layout
	case packMarker
	case inverse
	case valueMarker
}
