public enum SemanticType: CaseIterable, Codable, Sendable {
    case standard
    case comment
    case keyword
    case variable
    case typeName
    case numeric
    case argument
    case error
    case typeDeclaration
    case memberDeclaration
    case memberName
    case functionName
    case functionDeclaration
    case other
}
