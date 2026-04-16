import Foundation

public enum GenericFieldLayout {
    public typealias SpecializationGenericStructNonRequirement = GenericStructNonRequirement<String>

    public struct GenericStructNonRequirement<A> {
        public var field1: Double
        public var field2: A
        public var field3: Int
    }

    public struct GenericStructLayoutRequirement<A: AnyObject> {
        public var field1: Double
        public var field2: A
        public var field3: Int
    }

    public struct GenericStructSwiftProtocolRequirement<A: Equatable> {
        public var field1: Double
        public var field2: A
        public var field3: Int
    }

    public struct GenericStructObjCProtocolRequirement<A: NSCopying> {
        public var field1: Double
        public var field2: A
        public var field3: Int
    }

    public class GenericClassNonRequirement<A> {
        public var field1: Double
        public var field2: A
        public var field3: Int

        public init(field1: Double, field2: A, field3: Int) {
            self.field1 = field1
            self.field2 = field2
            self.field3 = field3
        }
    }

    public class GenericClassLayoutRequirement<A: AnyObject> {
        public var field1: Double
        public var field2: A
        public var field3: Int

        public init(field1: Double, field2: A, field3: Int) {
            self.field1 = field1
            self.field2 = field2
            self.field3 = field3
        }
    }

    public class GenericClassNonRequirementInheritNSObject<A>: NSObject {
        public var field1: Double
        public var field2: A
        public var field3: Int

        public init(field1: Double, field2: A, field3: Int) {
            self.field1 = field1
            self.field2 = field2
            self.field3 = field3
        }
    }

    public class GenericClassLayoutRequirementInheritNSObject<A: AnyObject>: NSObject {
        public var field1: Double
        public var field2: A
        public var field3: Int

        public init(field1: Double, field2: A, field3: Int) {
            self.field1 = field1
            self.field2 = field2
            self.field3 = field3
        }
    }
}
