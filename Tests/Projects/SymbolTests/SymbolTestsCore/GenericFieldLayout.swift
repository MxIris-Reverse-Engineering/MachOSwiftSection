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

    // MARK: - Generic helper types used as concrete instantiations below

    public struct Box<Element> {
        public var value: Element
    }

    public struct Pair<First, Second> {
        public var first: First
        public var second: Second
    }

    /// Single-payload generic enum whose payload uses the *second* parameter —
    /// a static computation must substitute parameter index 1, not blindly take
    /// the first generic argument.
    public enum SecondParameterPayloadEnum<First, Second> {
        case empty
        case payload(Second)
    }

    /// Multi-payload generic enum: each payload case uses a different parameter,
    /// so resolving its layout requires substituting both arguments.
    public enum TwoPayloadGenericEnum<First, Second> {
        case first(First)
        case second(Second)
    }

    public class GenericBaseClass<Element> {
        public var baseValue: Element

        public init(baseValue: Element) {
            self.baseValue = baseValue
        }
    }

    // MARK: - Non-generic holders of concrete bound-generic instantiations
    //
    // These are non-generic, so their runtime field-offset vector is reachable
    // via the metadata accessor — the ground truth `StaticLayoutVsRuntimeTests`
    // compares the static engine against. Each holder exercises a different
    // substitution path.

    /// Struct fields whose layout depends on the type argument (`field2: A`).
    public struct ConcreteGenericStructFieldHolder {
        public var leading: Int
        public var intInstance: GenericStructNonRequirement<Int>
        public var stringInstance: GenericStructNonRequirement<String>
        public var trailing: Int
    }

    /// A bound-generic field nested inside another bound-generic field.
    public struct NestedGenericFieldHolder {
        public var leading: Int
        public var nested: Pair<Box<Int>, Int>
        public var trailing: Int
    }

    /// `Optional` wrapping a concrete instantiation (the payload must be the
    /// substituted inner type).
    public struct OptionalGenericFieldHolder {
        public var leading: Int
        public var optional: Box<Int>?
        public var trailing: Int
    }

    /// A tuple of concrete instantiations (substitution must reach tuple
    /// elements).
    public struct TupleGenericFieldHolder {
        public var leading: Int
        public var tuple: (Box<Int>, Box<String>)
        public var trailing: Int
    }

    /// Single-payload generic enum field — verifies the payload picks the
    /// correct (second) parameter.
    public struct SinglePayloadGenericEnumFieldHolder {
        public var leading: Int
        public var enumField: SecondParameterPayloadEnum<Bool, Int64>
        public var trailing: Int
    }

    /// Multi-payload generic enum field — verifies each payload parameter is
    /// substituted.
    public struct MultiPayloadGenericEnumFieldHolder {
        public var leading: Int
        public var enumField: TwoPayloadGenericEnum<Int, Double>
        public var trailing: Int
    }

    /// A generic *class* field stays a single reference (no recursion); this
    /// must not regress.
    public struct ClassReferenceGenericFieldHolder {
        public var leading: Int
        public var classReference: GenericClassNonRequirement<Int>
        public var trailing: Int
    }

    /// Frozen stdlib generics whose layout is argument-independent — must keep
    /// resolving by bare name through the frozen table, not via the new
    /// instantiation path.
    public struct FrozenGenericFieldHolder {
        public var leading: Int
        public var array: [Int]
        public var pointer: UnsafePointer<Double>
        public var trailing: Int
    }

    /// A non-generic class deriving from a concrete generic superclass: its own
    /// field must start after `GenericBaseClass<Int>`'s instance size.
    public class ConcreteGenericSuperclassSubclass: GenericBaseClass<Int> {
        public var ownValue: Int

        public init(baseValue: Int, ownValue: Int) {
            self.ownValue = ownValue
            super.init(baseValue: baseValue)
        }
    }
}
