public enum Structs {
    private enum PrivateProtocolTest: Protocols.ProtocolTest {
        case empty

        var body: some Protocols.ProtocolTest {
            fatalError()
        }

        static var body: Body? {
            fatalError()
        }
    }

    public struct StructTest: Protocols.ProtocolTest {

        public var body: some Protocols.ProtocolTest {
            PrivateProtocolTest.empty
        }

        public static var body: some Protocols.ProtocolTest {
            PrivateProtocolTest.empty
        }
    }
}

extension Structs.StructTest: Protocols.ProtocolWitnessTableTest {
    public func a() {
        print(GenericFieldLayout.GenericStructNonRequirement<Self>(field1: 0.1, field2: self, field3: 1))
    }

    public func b() {}

    public func c() {}

    public func d() {}

    public func e() {}
}
