// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// ValueWitnessFlags is a pure raw-value bit decoder (no MachO
// dependency). The baseline embeds canonical synthetic raw
// values exercising each documented bit field.

enum ValueWitnessFlagsBaseline {
    static let registeredTestMethodNames: Set<String> = ["alignment", "alignmentMask", "hasEnumWitnesses", "hasSpareBits", "inComplete", "init(rawValue:)", "isBitwiseBorrowable", "isBitwiseTakable", "isCopyable", "isIncomplete", "isInlineStorage", "isNonBitwiseBorrowable", "isNonBitwiseTakable", "isNonCopyable", "isNonInline", "isNonPOD", "isPOD", "maxNumExtraInhabitants", "rawValue"]

    struct Entry {
        let rawValue: UInt32
        let alignmentMask: UInt64
        let alignment: UInt64
        let isPOD: Bool
        let isInlineStorage: Bool
        let isBitwiseTakable: Bool
        let isBitwiseBorrowable: Bool
        let isCopyable: Bool
        let hasEnumWitnesses: Bool
        let isIncomplete: Bool
    }

    static let cases: [Entry] = [
        // podStruct
        Entry(
            rawValue: 0x7,
            alignmentMask: 0x7,
            alignment: 0x8,
            isPOD: true,
            isInlineStorage: true,
            isBitwiseTakable: true,
            isBitwiseBorrowable: true,
            isCopyable: true,
            hasEnumWitnesses: false,
            isIncomplete: false
        ),
        // nonPodReference
        Entry(
            rawValue: 0x110007,
            alignmentMask: 0x7,
            alignment: 0x8,
            isPOD: false,
            isInlineStorage: true,
            isBitwiseTakable: false,
            isBitwiseBorrowable: false,
            isCopyable: true,
            hasEnumWitnesses: false,
            isIncomplete: false
        ),
        // nonInlineStorage
        Entry(
            rawValue: 0x20007,
            alignmentMask: 0x7,
            alignment: 0x8,
            isPOD: true,
            isInlineStorage: false,
            isBitwiseTakable: true,
            isBitwiseBorrowable: true,
            isCopyable: true,
            hasEnumWitnesses: false,
            isIncomplete: false
        ),
        // enumWithSpareBits
        Entry(
            rawValue: 0x280007,
            alignmentMask: 0x7,
            alignment: 0x8,
            isPOD: true,
            isInlineStorage: true,
            isBitwiseTakable: true,
            isBitwiseBorrowable: true,
            isCopyable: true,
            hasEnumWitnesses: true,
            isIncomplete: false
        ),
        // incomplete
        Entry(
            rawValue: 0x400007,
            alignmentMask: 0x7,
            alignment: 0x8,
            isPOD: true,
            isInlineStorage: true,
            isBitwiseTakable: true,
            isBitwiseBorrowable: true,
            isCopyable: true,
            hasEnumWitnesses: false,
            isIncomplete: true
        ),
        // nonCopyable
        Entry(
            rawValue: 0x800007,
            alignmentMask: 0x7,
            alignment: 0x8,
            isPOD: true,
            isInlineStorage: true,
            isBitwiseTakable: true,
            isBitwiseBorrowable: true,
            isCopyable: false,
            hasEnumWitnesses: false,
            isIncomplete: false
        ),
        // nonBitwiseBorrowable
        Entry(
            rawValue: 0x1000007,
            alignmentMask: 0x7,
            alignment: 0x8,
            isPOD: true,
            isInlineStorage: true,
            isBitwiseTakable: true,
            isBitwiseBorrowable: false,
            isCopyable: true,
            hasEnumWitnesses: false,
            isIncomplete: false
        )
    ]
}
