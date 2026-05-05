// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
// Source: InProcess (`CoreFoundation.CFString.self`); no SymbolTestsCore section presence.
//
// ForeignClassMetadata is the metadata kind the Swift compiler
// emits for CoreFoundation foreign classes (CFString, CFArray, etc.).
// The metadata lives in CoreFoundation; Swift uses
// `unsafeBitCast(CFString.self, to: UnsafeRawPointer.self)` to
// obtain the metadata pointer at runtime. Phase B6 introduced
// `ForeignTypeFixtures` to surface CFString/CFArray references
// in SymbolTestsCore so the bridging usage is documented; the
// canonical carrier is CoreFoundation's own runtime metadata.
//
// `init(layout:offset:)` is filtered as memberwise-synthesized.

enum ForeignClassMetadataBaseline {
    static let registeredTestMethodNames: Set<String> = ["classDescriptor", "layout", "offset"]

    struct Entry {
        let kindRawValue: UInt64
    }

    static let coreFoundationCFString = Entry(
        kindRawValue: 0x203
    )
}
