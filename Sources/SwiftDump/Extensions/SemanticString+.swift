import Semantic

extension SemanticString {
    func replacingTypeNameOrOtherToTypeDeclaration() -> SemanticString {
        replacing {
            switch $0 {
            case .type(let type, .name):
                return .type(type, .declaration)
            case .other:
                return .type(.other, .declaration)
            default:
                return $0
            }
        }
    }
}
