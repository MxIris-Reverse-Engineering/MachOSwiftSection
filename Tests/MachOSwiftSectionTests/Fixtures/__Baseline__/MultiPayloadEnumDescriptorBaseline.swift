// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum MultiPayloadEnumDescriptorBaseline {
    static let registeredTestMethodNames: Set<String> = ["actualSize", "contents", "contentsSizeInWord", "flags", "layout", "mangledTypeName", "offset", "payloadSpareBitMaskByteCount", "payloadSpareBitMaskByteCountIndex", "payloadSpareBitMaskByteOffset", "payloadSpareBits", "payloadSpareBitsIndex", "sizeFlagsIndex", "usesPayloadSpareBits"]

    struct Entry {
        let offset: Int
        let layoutSizeFlags: UInt32
        let mangledTypeNameRawString: String
        let contentsSizeInWord: UInt32
        let flags: UInt32
        let usesPayloadSpareBits: Bool
        let sizeFlagsIndex: Int
        let payloadSpareBitMaskByteCountIndex: Int
        let payloadSpareBitsIndex: Int
        let actualSize: Int
        let contentsCount: Int
        let payloadSpareBitsCount: Int
        let payloadSpareBitMaskByteOffset: UInt32
        let payloadSpareBitMaskByteCount: UInt32
    }

    static let multiPayloadEnumTest = Entry(
    offset: 0x3d884,
    layoutSizeFlags: 0x10000,
    mangledTypeNameRawString: "\u{1}",
    contentsSizeInWord: 0x1,
    flags: 0x0,
    usesPayloadSpareBits: false,
    sizeFlagsIndex: 0,
    payloadSpareBitMaskByteCountIndex: 1,
    payloadSpareBitsIndex: 1,
    actualSize: 8,
    contentsCount: 1,
    payloadSpareBitsCount: 0,
    payloadSpareBitMaskByteOffset: 0x0,
    payloadSpareBitMaskByteCount: 0x0
    )
}
