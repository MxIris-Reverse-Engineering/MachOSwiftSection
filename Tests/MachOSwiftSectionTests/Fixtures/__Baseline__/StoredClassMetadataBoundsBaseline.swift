// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
// Source fixture: SymbolTestsCore.framework
//
// StoredClassMetadataBounds is reachable via
// ClassDescriptor.resilientMetadataBounds(in:context:). Phase B2
// converted the Suite to an InProcess-only real test against
// `ResilientClassFixtures.ResilientChild` (parent
// `SymbolTestsHelper.ResilientBase`, cross-module). The bounds
// are runtime-allocated so no ABI literal is pinned — the Suite
// asserts invariants on the resolved record instead.
//
// `init(layout:offset:)` is filtered as memberwise-synthesized.

enum StoredClassMetadataBoundsBaseline {
    static let registeredTestMethodNames: Set<String> = ["layout", "offset"]
}
