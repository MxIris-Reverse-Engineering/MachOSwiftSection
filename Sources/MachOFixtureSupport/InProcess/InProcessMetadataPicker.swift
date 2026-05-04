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
    ///
    /// Note: `Any.self` has flags `0x80000000` (bit 31 set →
    /// `classConstraint == .any`). Calling `flags.classConstraint` traps
    /// because the source's accessor does `UInt8(rawValue & 0x80000000)`,
    /// which overflows for any value ≥ 256. Tests that exercise
    /// `classConstraint` / `isClassBounded` / `isObjC` / `representation`
    /// must therefore use `stdlibAnyObjectExistential` instead.
    package nonisolated(unsafe) static let stdlibAnyExistential: UnsafeRawPointer = {
        unsafeBitCast(Any.self, to: UnsafeRawPointer.self)
    }()

    /// `AnyObject.self` — class-bounded existential with zero witness tables
    /// (flags `0x0`). Safe substitute for `stdlibAnyExistential` when a test
    /// needs to call `flags.classConstraint`.
    package nonisolated(unsafe) static let stdlibAnyObjectExistential: UnsafeRawPointer = {
        unsafeBitCast(AnyObject.self, to: UnsafeRawPointer.self)
    }()

    /// `(any Sequence<Int>).self` — covers `ExtendedExistentialTypeMetadata`
    /// (with shape) and `ExtendedExistentialTypeShape`.
    ///
    /// Note: parameterized protocol existentials (with primary associated
    /// types) are the only existentials whose runtime metadata kind is
    /// `extendedExistential` (0x307). Bare existentials like `(any Equatable)`
    /// or `Any` produce kind `existential` (0x303). The constant name retains
    /// `stdlibAnyEquatable` for plan continuity, but the underlying type is
    /// `(any Sequence<Int>)` because `Equatable` lacks a primary associated
    /// type. Parameterized protocol existential metadata requires macOS
    /// 13.0+ at the language-runtime level.
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    package nonisolated(unsafe) static let stdlibAnyEquatable: UnsafeRawPointer = {
        unsafeBitCast((any Sequence<Int>).self, to: UnsafeRawPointer.self)
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
