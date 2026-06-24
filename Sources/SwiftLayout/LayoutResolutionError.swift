/// Why a particular field's (or nested type's) layout could not be computed
/// statically. Surfaced per-field via `FieldResolution.unknown` so that a
/// single unresolvable field degrades only itself and the fields after it,
/// never the whole aggregate.
public enum LayoutUnknownReason: Sendable, Hashable {
    /// A field type is resilient and its defining module is not available in
    /// the current single-image scope (resolved by the dependency closure in a
    /// later phase).
    case resilientFieldUnresolved
    /// A field type lives in a dependency image that could not be located.
    case missingDependencyImage(installName: String)
    /// A class has an Objective-C ancestor whose `class_ro_t` could not be
    /// located in the current image scope (e.g. the single-image engine, or a
    /// closure that does not reach the framework defining it), so its instance
    /// size — the start offset for this class's own fields — is unknown.
    case objCAncestorUnresolved(className: String)
    /// The demangled type node has a kind the engine does not yet handle
    /// (existential, function, reference storage, …). Carries the kind's name.
    case unsupportedTypeKind(nodeKindName: String)
    /// The demangled type resolved to a fully-qualified name that has no
    /// descriptor in the current image scope.
    case typeDescriptorNotFound(qualifiedTypeName: String)
    /// A generic parameter was encountered with no substitution available
    /// (generic substitution is a later phase).
    case genericParameterUnsubstituted
    /// A layout dependency cycle was detected while recursing.
    case cyclicLayout
    /// The field's mangled type name could not be demangled.
    case demangleFailure
    /// An earlier field in the same aggregate could not be resolved, so the
    /// running offset accumulator is no longer trustworthy for this field.
    case precedingFieldUnresolved
}

/// Internal error thrown while resolving a layout; caught at the aggregate
/// boundary and converted into a per-field `FieldResolution.unknown`.
enum LayoutResolutionError: Error {
    case unknown(LayoutUnknownReason)
}
