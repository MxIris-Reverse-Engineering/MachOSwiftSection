import Foundation
import MachOSwiftSectionC

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

    // MARK: - ObjC class wrapper

    /// `NSObject.self` — an unmodified ObjC class. The Swift runtime
    /// represents pure ObjC class metadata through an
    /// `ObjCClassWrapperMetadata` (kind 0x305) whose `objcClass` field
    /// points at the actual ObjC class metadata. This is the canonical
    /// in-process source for `ObjCClassWrapperMetadataTests` (Phase B3).
    package nonisolated(unsafe) static let foundationNSObjectWrapper: UnsafeRawPointer = {
        unsafeBitCast(NSObject.self, to: UnsafeRawPointer.self)
    }()

    // MARK: - foreign class

    /// `CFString.self` — a CoreFoundation type imported as a Swift
    /// foreign class. The Swift compiler emits `ForeignClassMetadata`
    /// (kind 0x203) for such types; the metadata lives in CoreFoundation
    /// and is reached via `unsafeBitCast(CFString.self, ...)`. This is
    /// the canonical in-process source for `ForeignClassMetadataTests`
    /// (Phase B6).
    package nonisolated(unsafe) static let coreFoundationCFString: UnsafeRawPointer = {
        unsafeBitCast(CFString.self, to: UnsafeRawPointer.self)
    }()
}

extension InProcessMetadataPicker {
    /// Returns a metadata pointer for SymbolTestsCore's nominal type by
    /// dlsym'ing the type's metadata accessor function and invoking it.
    ///
    /// `symbol` is the Swift mangled C symbol of the metadata accessor
    /// (no leading underscore — `dlsym` adds it), e.g.
    /// `$s15SymbolTestsCore7ClassesO9ClassTestCMa`.
    ///
    /// The fixture binary is loaded into the current process on first
    /// call (idempotent). In the test process, `MachOSwiftSectionFixtureTests`
    /// has already loaded it; this function's `dlopen` is then a no-op.
    /// In the standalone `baseline-generator` process, this function's
    /// load is the one that brings the framework's symbols into scope.
    package static func fixtureMetadata(symbol: String) throws -> UnsafeRawPointer {
        // Ensure the SymbolTestsCore fixture binary is dlopen'd into the
        // current process. In the test process, MachOSwiftSectionFixtureTests
        // already does this; calling here is a no-op the second time. In the
        // standalone baseline-generator process, this is the only path that
        // loads the framework.
        try ensureFixtureLoaded()
        guard let handle = dlopen(nil, RTLD_NOW) else {
            throw FixtureLoadError.imageNotFoundAfterDlopen(path: "<self>", dlerror: nil)
        }
        guard let accessorAddress = dlsym(handle, symbol) else {
            throw FixtureLoadError.imageNotFoundAfterDlopen(
                path: symbol,
                dlerror: dlerror().map { String(cString: $0) }
            )
        }
        // Type metadata accessor signature: `MetadataResponse(MetadataRequest)`
        // with `swiftcall` calling convention. Swift `@convention(c)` cannot
        // express a struct return that matches `swiftcc`, so dispatch through
        // the C wrapper that uses `__attribute__((swiftcall))` internally.
        // For non-generic types, pass MetadataRequest(0) and return the
        // metadata pointer from the response.
        let response = swift_section_callAccessor0(accessorAddress, 0)
        guard let metadataPointer = response.Metadata else {
            throw FixtureLoadError.imageNotFoundAfterDlopen(
                path: symbol,
                dlerror: "metadata accessor returned nil"
            )
        }
        return UnsafeRawPointer(metadataPointer)
    }

    /// Returns the address of a fixture-binary symbol by resolving it via
    /// `dlsym` against the in-process image. Use this to obtain the address
    /// of a Swift descriptor (e.g. `...Mn`) or any other static symbol
    /// without invoking it through a metadata accessor.
    ///
    /// `symbol` is the Swift mangled C symbol (no leading underscore —
    /// `dlsym` adds it).
    package static func fixtureSymbol(_ symbol: String) throws -> UnsafeRawPointer {
        try ensureFixtureLoaded()
        guard let handle = dlopen(nil, RTLD_NOW) else {
            throw FixtureLoadError.imageNotFoundAfterDlopen(path: "<self>", dlerror: nil)
        }
        guard let address = dlsym(handle, symbol) else {
            throw FixtureLoadError.imageNotFoundAfterDlopen(
                path: symbol,
                dlerror: dlerror().map { String(cString: $0) }
            )
        }
        return UnsafeRawPointer(address)
    }

    /// Idempotently dlopens `SymbolTestsCore.framework` so that subsequent
    /// `dlsym(RTLD_NOW, ...)` calls can locate fixture-binary symbols.
    /// Resolves the framework path relative to this source file, mirroring
    /// `MachOSwiftSectionFixtureTests.dlopenOnce` so the test process and
    /// the standalone `baseline-generator` process behave identically.
    private static func ensureFixtureLoaded() throws {
        _ = dlopenOnce
    }

    private static let dlopenOnce: Void = {
        let absolute = resolveFixturePath(MachOImageName.SymbolTestsCore.rawValue)
        _ = absolute.withCString { dlopen($0, RTLD_LAZY) }
    }()

    /// Resolve a relative `MachOImageName` path (rooted at the package-relative
    /// `../../Tests/...` convention used by `loadFromFile`) to an absolute path.
    ///
    /// Caveat: `MachOImageName.SymbolTestsCore.rawValue` is rooted as if the
    /// caller lives in `Sources/<TopLevelTarget>/Foo.swift`, i.e. exactly two
    /// `../` hops to reach the package root. This file lives one level deeper
    /// in `Sources/MachOFixtureSupport/InProcess/`, so we anchor against
    /// `Sources/MachOFixtureSupport/` (one path component up from `#filePath`'s
    /// parent) to make the existing `../../...` rawValue resolve correctly.
    private static func resolveFixturePath(_ relativePath: String) -> String {
        if relativePath.hasPrefix("/") { return relativePath }
        let parentOfThisFile = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let oneLevelUp = parentOfThisFile.deletingLastPathComponent()
        let url = URL(fileURLWithPath: relativePath, relativeTo: oneLevelUp)
        return url.standardizedFileURL.path
    }
}
