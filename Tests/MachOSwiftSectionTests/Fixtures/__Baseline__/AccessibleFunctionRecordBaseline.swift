// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// Two accessible function records: a non-generic distributed target
// (null generic environment) and the one generic target (non-null).
// Live MangledName payloads aren't embedded as literals; the
// companion Suite verifies the function type resolves
// cross-reader-consistently against the presence flag recorded here.

enum AccessibleFunctionRecordBaseline {
    static let registeredTestMethodNames: Set<String> = ["flags", "functionAddress", "functionOffset", "functionType", "genericEnvironment", "genericEnvironmentOffset", "isDistributed", "layout", "name", "offset"]

    struct Entry {
        let offset: Int
        let name: String
        let functionOffset: Int?
        let genericEnvironmentOffset: Int?
        let flagsRawValue: UInt32
        let isDistributed: Bool
        let hasFunctionType: Bool
    }

    static let nonGeneric = Entry(
    offset: 0x5060c,
    name: "$s15SymbolTestsCore17DistributedActorsO0D9ActorTestC12remoteMethod5valueS2i_tYaKFTE",
    functionOffset: 0x3ae78,
    genericEnvironmentOffset: nil,
    flagsRawValue: 0x1,
    isDistributed: true,
    hasFunctionType: true
    )

    static let generic = Entry(
    offset: 0x50648,
    name: "$s15SymbolTestsCore17DistributedActorsO07GenericD9ActorTestC7process7elementxx_tYaKFTE",
    functionOffset: 0x3afe0,
    genericEnvironmentOffset: 0x46af0,
    flagsRawValue: 0x1,
    isDistributed: true,
    hasFunctionType: true
    )

    static let recordCount = 4
}
