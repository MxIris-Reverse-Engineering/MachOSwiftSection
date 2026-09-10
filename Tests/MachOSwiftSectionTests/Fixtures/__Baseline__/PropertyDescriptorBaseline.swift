// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// Four property descriptors, one per shape: the module's shared
// trivial one, a struct stored property whose offset is inline in the
// header, a generic struct's stored property whose offset lives in
// the metadata, and a resilient class's settable computed property.

enum PropertyDescriptorBaseline {
    static let registeredTestMethodNames: Set<String> = ["bodyOffset", "bodySize", "computedPropertyBody", "header", "inlineStoredFieldOffset", "isTrivial", "layout", "offset", "size", "storedFieldOffset"]

    struct Entry {
        let offset: Int
        let headerRawValue: UInt32
        let isTrivial: Bool
        let bodySize: Int
        let size: Int
        let bodyOffset: Int
        let inlineStoredFieldOffsetRawValue: UInt32?
        let storedFieldOffsetRawValue: UInt32?
        let computedGetterOffset: Int?
    }

    static let trivial = Entry(
    offset: 0x3f400,
    headerRawValue: 0x0,
    isTrivial: true,
    bodySize: 0,
    size: 4,
    bodyOffset: 0x3f404,
    inlineStoredFieldOffsetRawValue: nil,
    storedFieldOffsetRawValue: nil,
    computedGetterOffset: nil
    )

    static let inlineStoredOffset = Entry(
    offset: 0x3dcd8,
    headerRawValue: 0x1800000,
    isTrivial: false,
    bodySize: 0,
    size: 4,
    bodyOffset: 0x3dcdc,
    inlineStoredFieldOffsetRawValue: 0x0,
    storedFieldOffsetRawValue: 0x0,
    computedGetterOffset: nil
    )

    static let unresolvedFieldOffset = Entry(
    offset: 0x38b80,
    headerRawValue: 0x1fffffe,
    isTrivial: false,
    bodySize: 4,
    size: 8,
    bodyOffset: 0x38b84,
    inlineStoredFieldOffsetRawValue: nil,
    storedFieldOffsetRawValue: 0x20,
    computedGetterOffset: nil
    )

    static let computedSettable = Entry(
    offset: 0x56020,
    headerRawValue: 0x2400000,
    isTrivial: false,
    bodySize: 12,
    size: 16,
    bodyOffset: 0x56024,
    inlineStoredFieldOffsetRawValue: nil,
    storedFieldOffsetRawValue: nil,
    computedGetterOffset: 0x784c
    )
}
