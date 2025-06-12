public enum SemanticType: CaseIterable, Sendable {
    case standard
    case comment
    case keyword
    case variable
    case typeName
    case typeDeclaration
    case functionOrMethodName
    case functionOrMethodDeclaration
    case numeric
    case argument
    case memberDeclaration
    case memberName
    case error
}
