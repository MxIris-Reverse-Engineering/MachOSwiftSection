import Foundation

/// Static `UnsafeRawPointer` constants exposing Swift runtime metadata
/// for Suites that exercise `*Metadata` types without a fixture-binary
/// section presence (runtime-allocated metadata).
///
/// Each constant is a `unsafeBitCast(<TypeRef>.self, to: UnsafeRawPointer.self)`
/// — this is the standard idiom for obtaining a metadata pointer from a
/// Swift type reference. The pointer is stable for the test process's
/// lifetime; the Swift runtime uniques metadata.
///
/// Suites consume these via `MachOSwiftSectionFixtureTests.usingInProcessOnly(_:)`.
package enum InProcessMetadataPicker {
    // MARK: - stdlib metatype

    /// `type(of: Int.self)` — runtime-allocated `MetatypeMetadata` whose
    /// `instanceType` is `Int.self`. Exercises `MetatypeMetadata.kind` +
    /// `instanceType` chain.
    ///
    /// Note: `Int.self.self` is NOT the metatype metadata pointer — Swift
    /// folds `T.self.self` to `T.self` (same metadata pointer to the
    /// underlying type, kind 0x200/struct in this case). To obtain the
    /// `MetatypeMetadata` instance the runtime allocates for `Int.Type`,
    /// use `type(of: Int.self)`, which yields the `Int.Type.Type` value
    /// whose pointer is the metatype metadata (kind 0x304).
    package nonisolated(unsafe) static let stdlibIntMetatype: UnsafeRawPointer = {
        unsafeBitCast(type(of: Int.self), to: UnsafeRawPointer.self)
    }()

    // MARK: - stdlib tuple

    /// `(Int, String).self` — covers `TupleTypeMetadata` + `TupleTypeMetadata.Element`.
    package nonisolated(unsafe) static let stdlibTupleIntString: UnsafeRawPointer = {
        unsafeBitCast((Int, String).self, to: UnsafeRawPointer.self)
    }()

    // MARK: - stdlib function

    /// `((Int) -> Void).self` — covers `FunctionTypeMetadata` + `FunctionTypeFlags`.
    package nonisolated(unsafe) static let stdlibFunctionIntToVoid: UnsafeRawPointer = {
        unsafeBitCast(((Int) -> Void).self, to: UnsafeRawPointer.self)
    }()

    // MARK: - stdlib existential

    /// `Any.self` — covers `ExistentialTypeMetadata` for the maximally-general
    /// existential.
    package nonisolated(unsafe) static let stdlibAnyExistential: UnsafeRawPointer = {
        unsafeBitCast(Any.self, to: UnsafeRawPointer.self)
    }()

    /// `(any Equatable).self` — covers `ExtendedExistentialTypeMetadata` (with
    /// shape) and constrained existential.
    package nonisolated(unsafe) static let stdlibAnyEquatable: UnsafeRawPointer = {
        unsafeBitCast((any Equatable).self, to: UnsafeRawPointer.self)
    }()

    /// `(Any).Type.self` — covers `ExistentialMetatypeMetadata`.
    package nonisolated(unsafe) static let stdlibAnyMetatype: UnsafeRawPointer = {
        unsafeBitCast(Any.Type.self, to: UnsafeRawPointer.self)
    }()

    // MARK: - stdlib opaque

    /// `Int8.self` proxies for OpaqueMetadata; Swift runtime exposes opaque
    /// metadata via Builtin types but `Builtin.Int8` isn't visible outside
    /// the standard library, so use the user-visible `Int8` whose metadata
    /// includes the same opaque-metadata layout.
    package nonisolated(unsafe) static let stdlibOpaqueInt8: UnsafeRawPointer = {
        unsafeBitCast(Int8.self, to: UnsafeRawPointer.self)
    }()

    // MARK: - stdlib fixed array (macOS 26+ only)

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    package nonisolated(unsafe) static let stdlibInlineArrayInt3: UnsafeRawPointer = {
        unsafeBitCast(InlineArray<3, Int>.self, to: UnsafeRawPointer.self)
    }()
    #endif
}
