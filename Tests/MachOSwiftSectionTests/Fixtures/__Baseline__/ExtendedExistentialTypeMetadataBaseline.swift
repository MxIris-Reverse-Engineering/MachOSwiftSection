// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// ExtendedExistentialTypeMetadata is a runtime-allocated metadata
// shape with no static section emission. SymbolTestsCore declares
// primary-associated-type protocols (e.g. ProtocolPrimaryAssociated
// TypeTest), but the constrained metadata is materialised lazily
// via `swift_getExtendedExistentialType` — no live carrier is
// reachable from the static walks. The Suite asserts structural
// members behave against a synthetic memberwise instance.
//
// `init(layout:offset:)` is filtered as memberwise-synthesized.

enum ExtendedExistentialTypeMetadataBaseline {
    static let registeredTestMethodNames: Set<String> = ["layout", "offset"]
}
