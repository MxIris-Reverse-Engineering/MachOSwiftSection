import Demangling
extension DemanglingNode where Self: Sequence<Self> {
    package var accessorKind: AccessorKind {
        guard let node = first(of: .getter, .setter, .modifyAccessor, .readAccessor) else { return .none }
        switch node.kind {
        case .getter: return .getter
        case .setter: return .setter
        case .modifyAccessor: return .modifyAccessor
        case .readAccessor: return .readAccessor
        default: return .none
        }
    }
}
