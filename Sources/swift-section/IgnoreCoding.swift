import MachOExtensions

@propertyWrapper
struct IgnoreCoding<Value> {
    var wrappedValue: Value

    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}

extension IgnoreCoding: Codable where Value: OptionalProtocol {
    func encode(to encoder: Encoder) throws {
        // Skip encoding the wrapped value.
    }

    init(from decoder: Decoder) throws {
        // The wrapped value is simply initialised to nil when decoded.
        self.wrappedValue = nil
    }
}
