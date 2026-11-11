/// What the `@Observable` macro generated in a class, recovered at index time
/// (evolution proposal `observable-macro-folding`).
///
/// The macro rewrites each stored `var x` it tracks into a computed `x` — an
/// init accessor, a getter, a setter and a `_modify` that report to the
/// registrar — over private storage `_x`, adds the registrar
/// `_$observationRegistrar`, the methods `access(keyPath:)`,
/// `withMutation(keyPath:_:)` and the `shouldNotifyObservers(_:_:)`
/// overloads, and an `extension Model: Observation.Observable {}`. A stored
/// property declared `@ObservationIgnored`, and a `let`, it leaves alone.
///
/// The model keeps all of it as the binary has it — `_x` in
/// `TypeDefinition.fields`, the computed `x` in `variables`, the methods in
/// `functions` — because the ABI diff and snapshot records are built from
/// them. This description sits on top, for the interface printer, which
/// prints the class the way its source reads unless asked to expand macros,
/// and for a host that shows the expansion on its own.
public struct ObservableMacroExpansion: Sendable {
    /// A stored property the macro tracks: `var x` in the source, storage
    /// `_x` and a computed `x` in the binary.
    public struct TrackedProperty: Sendable, Equatable {
        /// Where the printable declaration of `x` comes from.
        public enum Origin: Sendable, Equatable {
            /// The computed `x` the macro generated has accessors in the
            /// image: it is the member variable `x` in `variables`.
            case declaredMember

            /// `x`'s accessors are stripped — an internal property of a
            /// release build with its local symbols removed, as in an OS
            /// framework or a shipped app — so no member variable stands for
            /// it, and its declaration is synthesized from the storage `_x`,
            /// which has the same type.
            case synthesized
        }

        /// What tells `_x` apart from a stored property the source declared
        /// with that name and `@ObservationIgnored`.
        public enum Evidence: Sendable, Equatable {
            /// `x` has an init accessor: only a property whose storage the
            /// macro moved to `_x` has one. Every image that keeps its local
            /// symbols carries it.
            case initAccessor

            /// The computed `x` the image exports has a setter or a `_modify`
            /// accessor and `_x`'s type.
            case accessors

            /// The exported initial-value expression is `x`'s: the source
            /// gave `x` the initial value, and the macro moved only its
            /// storage. A stored property of its own would carry the
            /// expression itself.
            case initialValueExpression

            /// Nothing in the image names `x`; the storage's name alone says
            /// it. An `@ObservationIgnored` property named `_y` in a class
            /// whose symbols are all stripped reads as the tracked `y` this
            /// way, which is why it is told apart from the others.
            case backingFieldName
        }

        /// The property's name (`x`).
        public let name: String

        /// The storage the macro generated (`_x`), a member of
        /// `TypeDefinition.fields`.
        public let backingFieldName: String

        public let origin: Origin

        public let evidence: Evidence

        public init(name: String, backingFieldName: String, origin: Origin, evidence: Evidence) {
            self.name = name
            self.backingFieldName = backingFieldName
            self.origin = origin
            self.evidence = evidence
        }
    }

    /// The properties the macro tracks, in the order of their storage in
    /// `TypeDefinition.fields` — the order the source declares them in.
    public let trackedProperties: [TrackedProperty]

    /// The stored `var`s the macro leaves alone, by field name — the source
    /// declares them `@ObservationIgnored`. A lazy property is here by its
    /// name, a wrapped property by its backing storage (`_x`); a `let` never
    /// is, the macro tracks no constant.
    public let ignoredStoredPropertyNames: [String]

    /// The methods the macro generated, as `TypeDefinition.functions` holds
    /// them: `access(keyPath:)`, `withMutation(keyPath:_:)` and those of the
    /// `shouldNotifyObservers(_:_:)` overloads the image keeps.
    public let generatedFunctions: [FunctionDefinition]

    public init(trackedProperties: [TrackedProperty], ignoredStoredPropertyNames: [String], generatedFunctions: [FunctionDefinition]) {
        self.trackedProperties = trackedProperties
        self.ignoredStoredPropertyNames = ignoredStoredPropertyNames
        self.generatedFunctions = generatedFunctions
    }
}
