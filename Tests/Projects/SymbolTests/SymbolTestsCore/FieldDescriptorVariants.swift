import Foundation

public enum FieldDescriptorVariants {
    public struct VarLetFieldTest {
        public var mutableField: Int
        public let immutableField: String
        public var mutableOptional: Double?
        public let immutableOptional: Int?

        public init(mutableField: Int, immutableField: String, mutableOptional: Double?, immutableOptional: Int?) {
            self.mutableField = mutableField
            self.immutableField = immutableField
            self.mutableOptional = mutableOptional
            self.immutableOptional = immutableOptional
        }
    }

    public class ReferenceFieldTest {
        public weak var weakVarField: AnyObject?
        public weak let weakLetField: AnyObject?
        public unowned var unownedVarField: AnyObject
        public unowned let unownedLetField: AnyObject
        public unowned(unsafe) var unownedUnsafeVarField: AnyObject
        public unowned(unsafe) let unownedUnsafeLetField: AnyObject
        public var strongVarField: AnyObject
        public let strongLetField: AnyObject
        init(reference: AnyObject) {
            self.weakVarField = reference
            self.weakLetField = reference
            self.unownedVarField = reference
            self.unownedLetField = reference
            self.unownedUnsafeVarField = reference
            self.unownedUnsafeLetField = reference
            self.strongVarField = reference
            self.strongLetField = reference
        }
    }

    public struct MangledNameVariantsTest<Element> {
        public var concreteInt: Int
        public var concreteString: String
        public var genericElement: Element
        public var arrayOfElement: [Element]
        public var dictionaryOfElement: [String: Element]
        public var optionalElement: Element?
        public var tupleField: (Int, Element)
        public var functionField: (Element) -> Int

        public init(
            concreteInt: Int,
            concreteString: String,
            genericElement: Element,
            arrayOfElement: [Element],
            dictionaryOfElement: [String: Element],
            optionalElement: Element?,
            tupleField: (Int, Element),
            functionField: @escaping (Element) -> Int
        ) {
            self.concreteInt = concreteInt
            self.concreteString = concreteString
            self.genericElement = genericElement
            self.arrayOfElement = arrayOfElement
            self.dictionaryOfElement = dictionaryOfElement
            self.optionalElement = optionalElement
            self.tupleField = tupleField
            self.functionField = functionField
        }
    }
}
