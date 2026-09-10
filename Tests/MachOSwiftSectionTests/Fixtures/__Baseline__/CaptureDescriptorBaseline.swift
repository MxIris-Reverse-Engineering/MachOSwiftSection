// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// Three capture descriptors, picked by shape: zero, one and two
// metadata sources. Captured types are symbolic-reference-bearing
// mangled names and are not embedded as literals; the metadata
// SOURCE expressions are plain ASCII (closure-binding indices) and
// are, because they are the one place the recipe language is
// visible.

enum CaptureDescriptorBaseline {
    static let registeredTestMethodNames: Set<String> = ["actualSize", "captureTypeRecords", "captureTypeRecordsOffset", "layout", "metadataSourceRecords", "metadataSourceRecordsOffset", "numberOfBindings", "numberOfCaptureTypes", "numberOfMetadataSources", "offset"]

    struct Entry {
        let offset: Int
        let numberOfCaptureTypes: Int
        let numberOfMetadataSources: Int
        let numberOfBindings: Int
        let actualSize: Int
        let captureTypeRecordsOffset: Int
        let metadataSourceRecordsOffset: Int
        let mangledMetadataSources: [String]
    }

    static let withoutMetadataSources = Entry(
    offset: 0x5039c,
    numberOfCaptureTypes: 1,
    numberOfMetadataSources: 0,
    numberOfBindings: 0,
    actualSize: 16,
    captureTypeRecordsOffset: 0x503a8,
    metadataSourceRecordsOffset: 0x503ac,
    mangledMetadataSources: []
    )

    static let withSingleMetadataSource = Entry(
    offset: 0x503dc,
    numberOfCaptureTypes: 1,
    numberOfMetadataSources: 1,
    numberOfBindings: 1,
    actualSize: 24,
    captureTypeRecordsOffset: 0x503e8,
    metadataSourceRecordsOffset: 0x503ec,
    mangledMetadataSources: ["B0"]
    )

    static let withMultipleMetadataSources = Entry(
    offset: 0x5057c,
    numberOfCaptureTypes: 1,
    numberOfMetadataSources: 2,
    numberOfBindings: 2,
    actualSize: 32,
    captureTypeRecordsOffset: 0x50588,
    metadataSourceRecordsOffset: 0x5058c,
    mangledMetadataSources: ["B0", "B1"]
    )

    static let descriptorCount = 35
}
