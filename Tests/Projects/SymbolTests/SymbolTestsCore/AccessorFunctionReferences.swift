import Foundation

/// Fixture types whose *field types* are always-noncopyable, forcing the
/// compiler to emit kind-9 (accessor-function) symbolic references in their
/// field records.
///
/// Two compiler paths produce kind-9 references (`GenReflection.cpp`,
/// `getTypeRefByFunction`):
///
/// 1. The deployment target's runtime demangler predates the type's mangling
///    (e.g. `~Copyable` *generic signatures* need the Swift 6.0 runtime).
///    This path can never fire in this fixture — the target deploys to
///    macOS 26, whose runtime demangles everything — which is why the fixture
///    historically contained no kind-9 reference at all.
/// 2. The field type is **always noncopyable**: reflection metadata for such
///    fields is gated behind a runtime capability check, so the compiler
///    always emits the accessor-function reference regardless of deployment
///    target. That is the path this namespace exercises.
///
/// Offline (`MachOFile`) these references are unresolvable by construction
/// (resolving means *executing* the referenced thunk), so both the dump and
/// interface paths must render the honest `accessor function at <offset>`
/// fallback — never an empty string. The regression this pins: the interface
/// node printers once dropped the node silently, producing dangling
/// `var resource: ` fields and invalid empty-parenthesis cases
/// (`case holding()`). See
/// `Documentations/Internal/AccessorFunctionReferenceRendering.md`.
public enum AccessorFunctionReferences {
    /// The minimal always-noncopyable field type: any field typed with it
    /// gets a kind-9 reference instead of a demanglable mangled name.
    public struct NoncopyableResourceTest: ~Copyable {
        public var fileDescriptor: Int

        public init(fileDescriptor: Int) {
            self.fileDescriptor = fileDescriptor
        }

        deinit {}
    }

    /// Generic noncopyable container, deliberately *unconditionally*
    /// noncopyable (no `Copyable where Wrapped: Copyable` extension): a bound
    /// instantiation like `NoncopyableGenericBoxTest<Int>` is still
    /// always-noncopyable, so a field of that type carries a kind-9 reference
    /// whose underlying type is a bound generic with an inverse-requirement
    /// signature — the `Attachment<AnyAttachable>` shape from swift-testing.
    public struct NoncopyableGenericBoxTest<Wrapped: ~Copyable>: ~Copyable {
        public var wrapped: Wrapped

        public init(wrapped: consuming Wrapped) {
            self.wrapped = wrapped
        }
    }

    /// Stored-field coverage: the first two fields render as
    /// `var …: accessor function at <offset>`; the trailing ordinary field
    /// pins that rendering continues past a kind-9 field instead of aborting
    /// the type.
    public struct NoncopyableFieldHolderTest: ~Copyable {
        public var resource: NoncopyableResourceTest
        public var boxedInteger: NoncopyableGenericBoxTest<Int>
        public var trailingOrdinaryField: Int

        public init(resource: consuming NoncopyableResourceTest, boxedInteger: consuming NoncopyableGenericBoxTest<Int>, trailingOrdinaryField: Int) {
            self.resource = resource
            self.boxedInteger = boxedInteger
            self.trailingOrdinaryField = trailingOrdinaryField
        }
    }

    /// Enum-case coverage: payload cases must render
    /// `case holding(accessor function at <offset>)` — parentheses around the
    /// honest fallback, exactly like the dump path — while the empty case
    /// stays bare. The historical failure shape was `case holding()`, which
    /// `swiftc` rejects.
    public enum NoncopyablePayloadEnumTest: ~Copyable {
        case holding(NoncopyableResourceTest)
        case boxed(NoncopyableGenericBoxTest<Int>)
        case empty

        public consuming func consumeFileDescriptor() -> Int {
            switch consume self {
            case .holding(let resource):
                let descriptor = resource.fileDescriptor
                _ = consume resource
                return descriptor
            case .boxed(let box):
                _ = consume box
                return 0
            case .empty:
                return -1
            }
        }
    }
}
