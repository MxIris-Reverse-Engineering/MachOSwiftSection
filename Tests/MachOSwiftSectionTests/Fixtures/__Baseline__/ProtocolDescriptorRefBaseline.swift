// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// ProtocolDescriptorRef has no live carrier in SymbolTestsCore; the
// baseline embeds synthetic storage bits to exercise the Swift/ObjC
// tagged-pointer split. The `liveObjc` entry pins the resolved name
// of the ObjC inheriting protocol's NSObjectProtocol witness.

enum ProtocolDescriptorRefBaseline {
    static let registeredTestMethodNames: Set<String> = ["dispatchStrategy", "forObjC", "forSwift", "init(storage:)", "isObjC", "name", "objcProtocol", "storage", "swiftProtocol"]

    struct Entry {
        let storage: UInt64
        let isObjC: Bool
        let dispatchStrategyRawValue: UInt8
    }

    struct LiveObjcEntry {
        let prefixOffset: Int
        let name: String
    }

    static let swift = Entry(
    storage: 0xdeadbeef0000,
    isObjC: false,
    dispatchStrategyRawValue: 0x1
    )

    static let objc = Entry(
    storage: 0xdeadbeef0001,
    isObjC: true,
    dispatchStrategyRawValue: 0x0
    )

    static let liveObjc = LiveObjcEntry(
    prefixOffset: 0x525d0,
    name: "NSObject"
    )
}
