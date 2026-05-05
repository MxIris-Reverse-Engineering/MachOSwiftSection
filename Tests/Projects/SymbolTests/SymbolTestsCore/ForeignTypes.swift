import CoreFoundation

// Fixtures producing references to foreign classes. CoreFoundation types
// (CFString, CFArray) are imported as foreign classes — the Swift compiler
// emits a `ForeignClassMetadata` record (kind 0x203) for them, with the
// metadata living in CoreFoundation rather than this fixture binary.
//
// Even though the metadata pointer originates from CoreFoundation, this
// namespace forces the fixture binary to reference the bridged types so
// the metadata is reliably mapped into the test process. The real
// `ForeignClassMetadata` carrier is reached via
// `unsafeBitCast(CFString.self, to: UnsafeRawPointer.self)` from the
// `MachOFixtureSupport` `InProcessMetadataPicker`.
//
// `ForeignReferenceTypeMetadata` requires C++ interop import
// (`SWIFT_SHARED_REFERENCE`); SymbolTestsCore does not enable C++
// interop, so no live carrier exists for that metadata kind. Its Suite
// stays sentinel.

public enum ForeignTypeFixtures {
    public static func foreignClassReference() -> CFString {
        "" as CFString
    }

    public static func foreignArrayReference() -> CFArray {
        [] as CFArray
    }
}
