import Foundation

public enum Enums {
    public enum MultiPayloadEnumTests {
        case closure(() -> Void)
        case object(NSObject)
        case tuple(a: Int, b: Double)
        case empty
    }

    public enum MultiPayloadEnumTests1 {
        case string(String)
        case data(Data)
        case nsNumber(Decimal)
        case date(Date)
        case url(URL)
        case attributedString(AttributedString)
    }

    public enum MultiPayloadEnumTests2 {
        case string(Swift.String)
        case data(Data)
        case nsNumber(NSNumber)
        case nsNumber1(NSNumber)
        case nsNumber2(NSNumber)
        case nsNumber3(NSNumber)
        case nsNumber4(NSNumber)
        case nsNumber5(NSNumber)
    }

    public enum NoPayloadEnumTest {
        case north
        case south
        case east
        case west
    }

    public enum SinglePayloadEnumTest {
        case value(String)
        case none
        case error
    }

    /// A class — a single object reference whose extra inhabitants are the
    /// reserved low addresses.
    public final class SinglePayloadBoxClass {
        public var value: Int
        public init(value: Int) { self.value = value }
    }

    /// A struct whose only stored property is a class reference. By the runtime
    /// rule (`swift_initStructMetadata`: "use the field with the most") it
    /// inherits the reference's extra inhabitants — it is NOT extra-inhabitant-less.
    public struct SinglePayloadBoxStruct {
        public var box: SinglePayloadBoxClass
    }

    /// A single-payload enum over `SinglePayloadBoxStruct` with two empty cases.
    /// The struct's inherited extra inhabitants absorb both empty cases, so the
    /// enum stays a single pointer (size 8) — it must NOT gain a tag byte
    /// (size 9). This is the shape that broke on real SwiftUI types
    /// (`Text.Style.TextStyleFont` over `Font`) when struct extra inhabitants
    /// were dropped to zero; it guards the propagation fix.
    public enum SinglePayloadOverStructTest {
        case wrapped(SinglePayloadBoxStruct)
        case first
        case second
    }

    public indirect enum IndirectEnumTest {
        case leaf(Int)
        case node(IndirectEnumTest, IndirectEnumTest)
    }

    /// An `indirect` **single-payload** enum with empty cases: the payload is
    /// a `Builtin.NativeObject` box reference, so the empty cases ride the
    /// heap pointer's extra inhabitants (`leaf` = null, `sentinel` = pointer
    /// value 1) and the enum stays pointer-sized — it must NOT be described
    /// as an overflow layout with an extra tag byte, which is what treating
    /// an indirect payload as extra-inhabitant-less used to produce.
    public indirect enum IndirectSinglePayloadEnumTest {
        case node(IndirectSinglePayloadEnumTest)
        case leaf
        case sentinel
    }

    public enum PartialIndirectEnumTest {
        case leaf(Int)
        indirect case node(PartialIndirectEnumTest, PartialIndirectEnumTest)
        indirect case chain(PartialIndirectEnumTest)
    }

    public enum RawValueEnumTest: Int {
        case first = 1
        case second = 2
        case third = 3

        public var description: String {
            switch self {
            case .first: "first"
            case .second: "second"
            case .third: "third"
            }
        }

        public func doubled() -> Int { rawValue * 2 }

        public static func fromString(_ string: String) -> Self? { nil }
    }

    public enum StringRawValueEnumTest: String {
        case hello = "hello"
        case world = "world"
    }

    public enum CaseIterableEnumTest: String, CaseIterable {
        case alpha
        case beta
        case gamma
    }

    @objc
    public enum ObjCEnumTest: Int {
        case first = 1
        case second = 2
        case third = 3
    }

    @frozen
    public enum LargeFrozenEnumTest {
        case alpha
        case beta
        case gamma
        case delta
        case epsilon
        case zeta
        case eta
        case theta
        case iota
        case kappa
    }

    public enum GenericPayloadEnumTest<Element> {
        case first(Element)
        case second(Element, Element)
        case empty
    }

    public enum FunctionReferenceCaseTest {
        case first(Int)
        case second(String)

        public static func selectFirst() -> (Int) -> FunctionReferenceCaseTest {
            FunctionReferenceCaseTest.first
        }
    }
}
