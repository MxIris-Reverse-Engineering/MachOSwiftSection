protocol OptionalProtocol: ExpressibleByNilLiteral {
    associatedtype Wrapped
    func asOptional() -> Optional<Wrapped>
    static func makeOptional(_ wrappedValue: Wrapped?) -> Self
}

extension Optional: OptionalProtocol {
    func asOptional() -> Optional<Wrapped> {
        self
    }
    
    static func makeOptional(_ wrappedValue: Wrapped?) -> Optional<Wrapped> {
        if let wrappedValue {
            return .some(wrappedValue)
        } else {
            return .none
        }
    }
}
