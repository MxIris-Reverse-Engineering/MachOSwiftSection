public protocol OptionalProtocol: ExpressibleByNilLiteral {
    associatedtype Wrapped
    static var none: Self { get }
    static func some(_ wrappedValue: Wrapped) -> Self
    func map<E, U>(_ transform: (Wrapped) throws(E) -> U) throws(E) -> U? where E: Error, U: ~Copyable
    func flatMap<E, U>(_ transform: (Wrapped) throws(E) -> U?) throws(E) -> U? where E: Error, U: ~Copyable
    var unsafelyUnwrapped: Wrapped { get }
}

extension Optional: OptionalProtocol {}
