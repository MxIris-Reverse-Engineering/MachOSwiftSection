import Foundation

public enum BuiltinTypeFields {
    public struct IntegerTypesTest {
        public var intField: Int
        public var int8Field: Int8
        public var int16Field: Int16
        public var int32Field: Int32
        public var int64Field: Int64
        public var uintField: UInt
        public var uint8Field: UInt8
        public var uint16Field: UInt16
        public var uint32Field: UInt32
        public var uint64Field: UInt64

        public init(
            intField: Int,
            int8Field: Int8,
            int16Field: Int16,
            int32Field: Int32,
            int64Field: Int64,
            uintField: UInt,
            uint8Field: UInt8,
            uint16Field: UInt16,
            uint32Field: UInt32,
            uint64Field: UInt64
        ) {
            self.intField = intField
            self.int8Field = int8Field
            self.int16Field = int16Field
            self.int32Field = int32Field
            self.int64Field = int64Field
            self.uintField = uintField
            self.uint8Field = uint8Field
            self.uint16Field = uint16Field
            self.uint32Field = uint32Field
            self.uint64Field = uint64Field
        }
    }

    public struct FloatingTypesTest {
        public var floatField: Float
        public var doubleField: Double
        public var float32Field: Float32
        public var float64Field: Float64

        public init(floatField: Float, doubleField: Double, float32Field: Float32, float64Field: Float64) {
            self.floatField = floatField
            self.doubleField = doubleField
            self.float32Field = float32Field
            self.float64Field = float64Field
        }
    }

    public struct PrimitiveTypesTest {
        public var boolField: Bool
        public var characterField: Character
        public var stringField: String

        public init(boolField: Bool, characterField: Character, stringField: String) {
            self.boolField = boolField
            self.characterField = characterField
            self.stringField = stringField
        }
    }

    public struct TupleBuiltinTest {
        public var pairField: (Int, Double)
        public var tripleField: (Int, Double, Bool)
        public var quadrupleField: (Int8, Int16, Int32, Int64)

        public init(pairField: (Int, Double), tripleField: (Int, Double, Bool), quadrupleField: (Int8, Int16, Int32, Int64)) {
            self.pairField = pairField
            self.tripleField = tripleField
            self.quadrupleField = quadrupleField
        }
    }
}
