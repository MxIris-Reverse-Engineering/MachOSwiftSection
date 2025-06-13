import MachOExtensions

@propertyWrapper
struct IgnoreCoding<Value> {
    var wrappedValue: Value

    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}

extension IgnoreCoding: Codable where Value: OptionalProtocol {
    func encode(to encoder: Encoder) throws {}

    init(from decoder: Decoder) throws { self.wrappedValue = nil }
}
