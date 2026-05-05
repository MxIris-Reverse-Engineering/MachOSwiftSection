// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// EnumFunctions baselines are reader-independent: the helper
// `getEnumTagCounts` is a pure function. The Suite asserts literal
// equality against the cases below.

enum EnumFunctionsBaseline {
    static let registeredTestMethodNames: Set<String> = ["numTagBytes", "numTags"]

    struct Entry {
        let payloadSize: UInt64
        let emptyCases: UInt32
        let payloadCases: UInt32
        let numTags: UInt32
        let numTagBytes: UInt32
    }

    static let cases: [Entry] = [
        Entry(
            payloadSize: 0x0,
            emptyCases: 0x0,
            payloadCases: 0x0,
            numTags: 0x0,
            numTagBytes: 0x0
        ),
        Entry(
            payloadSize: 0x0,
            emptyCases: 0x4,
            payloadCases: 0x0,
            numTags: 0x4,
            numTagBytes: 0x1
        ),
        Entry(
            payloadSize: 0x1,
            emptyCases: 0x100,
            payloadCases: 0x1,
            numTags: 0x2,
            numTagBytes: 0x1
        ),
        Entry(
            payloadSize: 0x4,
            emptyCases: 0x1,
            payloadCases: 0x2,
            numTags: 0x3,
            numTagBytes: 0x1
        ),
        Entry(
            payloadSize: 0x8,
            emptyCases: 0x10000,
            payloadCases: 0x0,
            numTags: 0x1,
            numTagBytes: 0x0
        )
    ]
}
