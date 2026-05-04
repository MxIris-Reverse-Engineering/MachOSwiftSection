// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
// Source fixture: SymbolTestsCore.framework
//
// DispatchClassMetadata mirrors libdispatch's runtime class
// layout (OS_object). It's not a Swift type descriptor and no
// static carrier is reachable from SymbolTestsCore. The Suite
// resolves the wrapper against `Classes.ClassTest.self`'s runtime
// class metadata pointer (via dlsym + the C metadata accessor)
// and exercises the wrapper accessor surface. No ABI literal is
// pinned because the `kind` slot is the descriptor / isa pointer
// and the `offset` slot is the runtime metadata pointer
// bit-pattern — both ASLR-randomized per process.
//
// `init(layout:offset:)` is filtered as memberwise-synthesized.

enum DispatchClassMetadataBaseline {
    static let registeredTestMethodNames: Set<String> = ["layout", "offset"]
}
