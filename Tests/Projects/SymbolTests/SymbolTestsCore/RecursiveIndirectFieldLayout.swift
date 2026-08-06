import Foundation

/// Mutually-recursive value types whose field graph contains a **cycle**, the
/// shape that made the nested expanded-field-offset walk blow up.
///
/// Modelled on `DVTIconKit`'s icon-spec tree, the type that first hit it:
/// a struct (`GeneratedIconPrimitiveReferenceSpec`) holds an optional generic
/// enum (`GeneratedIconPrimitiveValueSpec<String>`), and that enum has an
/// `indirect` case whose payload is the struct again. The indirection is what
/// makes the cycle representable at all — without it the pair would be
/// infinitely sized and would not compile.
///
/// Walking such a graph with only a depth limit enumerates every *path* up to
/// that depth instead of every *node*, which is exponential. These fixtures
/// pin the cycle guard that turns it back into a bounded walk.
public enum RecursiveIndirectFieldLayout {
    /// The struct half of the cycle: reaches the enum half through an
    /// `Optional`, so the walk descends struct → enum payload → struct.
    public struct ReferenceSpec {
        public var name: String
        /// Reaches the enum half through `Optional`, the shape `DVTIconKit`
        /// actually has. The static (offline) engine stops at `Swift.Optional`
        /// — a stdlib type outside the fixture's image universe — so the
        /// static suite uses `direct` instead; the runtime engine materializes
        /// it in-process and walks straight through.
        public var value: ValueSpec<String>?
        /// The same cycle without the `Optional` hop, so the static engine can
        /// reach it too. Legal as a stored property because `ValueSpec` is
        /// `indirect` — its recursive case is a boxed pointer, which is exactly
        /// what makes the cycle finite-sized and representable.
        public var direct: ValueSpec<String>
        public var weight: Int

        public init(name: String, value: ValueSpec<String>?, direct: ValueSpec<String>, weight: Int) {
            self.name = name
            self.value = value
            self.direct = direct
            self.weight = weight
        }
    }

    /// The enum half of the cycle.
    ///
    /// `indirect` is applied **per case**, not to the whole enum, for two
    /// reasons. It matches `DVTIconKit`'s shape (only the recursive cases are
    /// boxed there). And it keeps the guard honest: `literal` is an ordinary
    /// inline payload while `reference` / `pair` are boxed pointers, so a walk
    /// that treated the flag as a whole-enum property instead of a per-case one
    /// would visibly get one of the two wrong.
    ///
    /// A whole-enum `indirect` would additionally make every payload boxed and
    /// therefore make the layout independent of `Value` — an
    /// argument-independent generic multi-payload enum, whose spare-bits layout
    /// this repo's `SwiftLayout` engine only models as of upstream `4eeb3b4`
    /// (see `Internal/TaskReports/2026-08-05-generic-fixed-mpe-spare-bits.md`).
    /// Keeping `literal(Value)` inline keeps the layout argument-dependent and
    /// this fixture off that unrelated axis.
    public enum ValueSpec<Value> {
        case literal(Value)
        indirect case reference(ReferenceSpec)
        indirect case pair(ValueSpec<Value>, ValueSpec<Value>)
    }

    /// A whole-enum `indirect` declaration: every payload case is boxed, not
    /// just one. Pins that the guard keys off the per-case flag the runtime
    /// actually sets, rather than off a single hand-picked case.
    public indirect enum BoxedNode {
        case leaf(Int)
        case branch(BoxedNode, BoxedNode)
    }

    /// A struct that is *not* part of any cycle but nests several layers deep,
    /// so the tests can assert the guard does not clip legitimate nesting.
    public struct AcyclicNesting {
        public struct Inner {
            public struct Innermost {
                public var value: Int
                public var flag: Bool
            }

            public var innermost: Innermost
            public var label: String
        }

        public var inner: Inner
        public var count: Int
    }

    /// Keeps the metadata for the recursive types reachable so the linker and
    /// the Swift runtime both materialize them in the built fixture.
    public static func makeSample() -> ReferenceSpec {
        ReferenceSpec(
            name: "root",
            value: .pair(.literal("left"), .literal("right")),
            direct: .reference(ReferenceSpec(name: "nested", value: nil, direct: .literal("leaf"), weight: 1)),
            weight: 0
        )
    }

    public static func makeBoxedNode() -> BoxedNode {
        .branch(.leaf(1), .leaf(2))
    }

    public static func makeAcyclicNesting() -> AcyclicNesting {
        AcyclicNesting(
            inner: .init(innermost: .init(value: 1, flag: true), label: "inner"),
            count: 2
        )
    }
}
