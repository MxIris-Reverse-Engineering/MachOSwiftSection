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

    // MARK: - Value-generic (SE-0452) and parameter-pack (SE-0393) types

    /// A variadic generic struct whose single stored property is the expanded
    /// pack tuple.
    public struct VariadicPack<each Element> {
        public var values: (repeat each Element)
    }

    /// A scalar parameter alongside a pack parameter — parameter ordinals must
    /// stay aligned across the mixed argument list — with a pattern-wrapping
    /// expansion (`Optional<each Rest>`).
    public struct MixedScalarAndPack<First, each Rest> {
        public var first: First
        public var rest: (repeat (each Rest)?)
    }

    /// Forwards its own pack into another variadic type (the argument pack
    /// stays `Pack{PackExpansion(…)}` until substitution flattens it) and wraps
    /// each element in a nominal pattern.
    public struct VariadicForwarder<each Element> {
        public var forwarded: VariadicPack<repeat each Element>
        public var wrapped: (repeat Box<each Element>)
    }

    /// A value-generic struct: its `InlineArray` field depends on the
    /// enclosing `count` value parameter.
    public struct ValueGenericBuffer<let count: Int> {
        public var storage: InlineArray<count, Int8>
        public var tail: Int32
    }

    // MARK: - Non-generic holders of value-generic / pack instantiations

    /// Pack-argument fields: `(repeat each Element)` must flatten to the
    /// concrete elements — including the empty pack (a zero-sized field) and
    /// the single-element tuple collapse.
    public struct PackExpansionFieldHolder {
        public var leading: Int
        public var triple: VariadicPack<Int32, Int8, Int64>
        public var single: VariadicPack<Int16>
        public var empty: VariadicPack< >
        public var trailing: Int
    }

    /// A scalar parameter and a pack parameter mixed in one argument list.
    public struct MixedPackFieldHolder {
        public var leading: Int
        public var mixed: MixedScalarAndPack<Int, Bool, Int8>
        public var trailing: Int
    }

    /// A pack forwarded through another variadic type plus a pattern-wrapping
    /// expansion (`Box<each Element>`).
    public struct PackForwardingFieldHolder {
        public var leading: Int
        public var forwarder: VariadicForwarder<Int32, Bool>
        public var trailing: Int
    }

    /// A single-payload enum whose payload is a value-generic fixed array —
    /// the payload's extra inhabitants (from the `Bool` element) absorb the
    /// empty case, so the enum adds no tag byte. (Enums cannot declare a type
    /// pack themselves — the compiler rejects it — so packs reach enum layout
    /// only through struct/tuple payload types.)
    public struct FixedArrayPayloadEnumFieldHolder {
        public var leading: Int
        public var enumField: SecondParameterPayloadEnum<Bool, InlineArray<3, Bool>>
        public var trailing: Int8
    }

    /// Value-generic and fixed-array fields, including extra-inhabitant
    /// propagation from the array element (`InlineArray<3, Bool>?` adds no tag
    /// byte).
    public struct ValueGenericFieldHolder {
        public var leading: Int
        public var buffer: ValueGenericBuffer<5>
        public var inline: InlineArray<3, Int64>
        public var optionalInline: InlineArray<3, Bool>?
        public var trailing: Int
    }

    /// A tuple's extra inhabitants come from its richest element (`Bool`), so
    /// the optional adds no tag byte and `trailing` starts right after the
    /// tuple's three bytes.
    public struct TupleExtraInhabitantFieldHolder {
        public var leading: Int
        public var optionalTuple: (Int16, Bool)?
        public var trailing: Int8
    }

    // MARK: - Nested types inside specialized generic parents, associated types,
    //         and constrained existentials

    /// A generic struct with a non-generic nested type. When the nested type is
    /// referenced as a field of a *specialized* parent (`Outer<Int>.Inner`), the
    /// field's mangled type carries a `boundGeneric*` parent context whose
    /// qualified name must keep the parent chain (`Outer.Inner`), not degrade to
    /// a bare `Inner`.
    public struct GenericOuter<Value> {
        public var value: Value

        public struct Inner {
            public var flag: Bool
            public var count: Int32
        }

        public enum InnerEnum {
            case none
            case some(Int16)
        }
    }

    /// Non-generic holder whose fields are nested types of a *specialized*
    /// generic parent — exercises the parent-chain-preserving name resolution.
    public struct NestedInSpecializedParentFieldHolder {
        public var leading: Int
        public var innerStruct: GenericOuter<Int>.Inner
        public var innerEnum: GenericOuter<String>.InnerEnum
        public var trailing: Int8
    }

    /// A generic struct whose stored fields are *associated types* of its own
    /// parameter's conformance (`C.Index`, `C.Element`). Reached as a concrete
    /// instantiation (`AssociatedTypeFieldHolder<[Int16]>` below), these resolve
    /// through the conformance's `__swift5_assocty` witnesses.
    public struct AssociatedTypeStorage<C: Collection> {
        public var index: C.Index
        public var element: C.Element
    }

    /// Non-generic holder of a concrete instantiation whose fields are
    /// associated types. For `Array<Int16>`: `Index == Int`, `Element == Int16`.
    public struct AssociatedTypeFieldHolder {
        public var leading: Int
        public var storage: AssociatedTypeStorage<[Int16]>
        public var trailing: Int8
    }

    /// A protocol with a primary associated type, for constrained existentials.
    public protocol Boxed<Wrapped> {
        associatedtype Wrapped
        var wrapped: Wrapped { get }
    }

    /// Non-generic holder whose fields are *constrained* existentials
    /// (`any Boxed<Int>`) — encoded via an extended existential type shape. The
    /// constraint does not change the container size versus `any Boxed`.
    public struct ConstrainedExistentialFieldHolder {
        public var leading: Int
        public var boxed: any Boxed<Int>
        public var optionalBoxed: (any Boxed<String>)?
        public var trailing: Int8
    }
}
